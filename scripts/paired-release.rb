#!/usr/bin/env ruby
# One draft contains both platforms; only --publish makes either one public.
require 'json'
require 'digest'
require 'open3'
require 'tmpdir'
require 'optparse'

module PairedRelease
  ROOT = File.expand_path('..', __dir__)
  REPO = 'kpathipan/dropdrive'
  def self.run(*args)
    out, err, status = Open3.capture3(*args, chdir: ROOT)
    raise "#{args.first} failed: #{err.strip}" unless status.success?
    out
  end
  def self.require!(value, message)
    raise message unless value
  end
  def self.json(path)
    JSON.parse(File.read(path))
  end
  def self.validate(version, mac_dir, win_dir, evidence_path, commit:, contract_path: File.join(ROOT, 'packaging/parity-contract.json'))
    require!(version.match?(/\A\d+\.\d+\.\d+\z/), 'Expected one stable X.Y.Z version for BOTH platforms')
    contract = json(contract_path)
    require!(!contract['releaseVersion'] || contract['releaseVersion'] == version, 'Version differs from shared release contract')
    contract_hash = Digest::SHA256.file(contract_path).hexdigest
    receipts = [json(File.join(mac_dir, 'mac-build.json')), json(File.join(win_dir, 'windows-build.json'))]
    paths = {}
    receipts.zip([['mac', mac_dir], ['windows', win_dir]]).each do |receipt, (platform, folder)|
      require!(receipt['schema'] == 1 && receipt['platform'] == platform, "Invalid #{platform} build receipt")
      require!(receipt['version'] == version && receipt['commit'] == commit, "#{platform}: version/commit does not match this release")
      require!(receipt['contract_sha256'] == contract_hash, "#{platform}: stale feature contract")
      required = platform == 'mac' ? %w[regressions performance keychain offline-engine media-fixtures signed-build] : %w[core-ui native-shell packaged-startup installed-upgrade]
      require!((required - receipt.fetch('checks')).empty?, "#{platform}: missing build checks")
      receipt.fetch('files').each do |file|
        name = file.fetch('name')
        require!(name == File.basename(name) && name != '.' && name != '..' && !name.include?('\\'), 'Unsafe artifact name')
        path = File.join(folder, name)
        require!(File.file?(path) && !File.symlink?(path) && File.size(path) > 0, "Missing artifact: #{name}")
        require!(Digest::SHA256.file(path).hexdigest == file['sha256'], "Artifact checksum mismatch: #{name}")
        require!(!paths.key?(name), "Duplicate release artifact: #{name}")
        paths[name] = path
      end
    end
    dmg = "DropDrive-v#{version}.dmg"
    required_files = [dmg, "com.dropdrive.windows-#{version}-full.nupkg", 'com.dropdrive.windows-win-Setup.exe', 'com.dropdrive.windows-win-Portable.zip', 'releases.win.json', 'RELEASES']
    require!((required_files - paths.keys).empty?, 'Both complete platform packages are required')
    feed = json(paths.fetch('releases.win.json')).fetch('Assets')
    require!(feed.any? { |a| a['PackageId'] == 'com.dropdrive.windows' && a['Version'] == version && a['Type'] == 'Full' }, 'Windows feed has no matching full package')
    feed.each do |asset|
      require!(asset['Version'] == version && paths.key?(asset['FileName']), 'Feed references another version or a missing package')
      path = paths.fetch(asset['FileName'])
      require!(asset['Size'] == File.size(path) && asset['SHA1'].to_s.downcase == Digest::SHA1.file(path).hexdigest, 'Windows feed size/SHA1 mismatch')
      require!(asset['SHA256'].to_s.downcase == Digest::SHA256.file(path).hexdigest, 'Windows feed SHA256 mismatch') if asset['SHA256']
    end
    evidence = json(evidence_path)
    require!(evidence['commit'] == commit && evidence['version'] == version && evidence['contract_sha256'] == contract_hash, 'Parity evidence is for another build or contract')
    missing = contract.fetch('features').flat_map do |feature|
      %w[mac windows].map do |platform|
        item = evidence.dig('features', feature, platform)
        "#{feature}/#{platform}" unless item && item['status'] == 'pass' && !item['evidence'].to_s.strip.empty?
      end.compact
    end
    require!(missing.empty?, "Parity NOT verified: #{missing.join(', ')}. UNAVAILABLE is not a pass.")
    [paths, dmg]
  end

  def self.main(argv)
    options = { mode: 'verify' }
    parser = OptionParser.new do |o|
      o.banner = 'Usage: ruby scripts/paired-release.rb --version X.Y.Z --mac-dir DIR --windows-dir DIR --evidence FILE [--notes FILE] [--stage|--publish]'
      %w[version mac-dir windows-dir evidence notes].each { |k| o.on("--#{k} VALUE") { |v| options[k.tr('-', '_').to_sym] = v } }
      o.on('--stage') { options[:mode] = 'stage' }
      o.on('--publish') { options[:mode] = 'publish' }
    end
    parser.parse!(argv)
    %i[version mac_dir windows_dir evidence].each { |k| require!(options[k], parser.to_s) }
    commit = run('git', 'rev-parse', 'HEAD').strip
    require!(run('git', 'status', '--porcelain').strip.empty?, 'Commit source changes before preparing/publishing a paired release')
    paths, dmg = validate(options[:version], options[:mac_dir], options[:windows_dir], options[:evidence], commit: commit)
    puts 'PASS paired release: matching versions/commit, both packages, hashes and all feature evidence'
    return if options[:mode] == 'verify'
    require!(options[:notes] && File.file?(options[:notes]), 'Release notes are required')
    tag = "v#{options[:version]}"
    body = File.read(options[:notes]) + "\n\nMac + Windows · same release · #{commit}\nsha256: #{Digest::SHA256.file(paths.fetch(dmg)).hexdigest}\n"
    if options[:mode] == 'stage'
      # No clobber, force-tag or overwrite: an existing draft/release is an error.
      Dir.mktmpdir('dropdrive-paired-notes-') do |tmp|
        notes = File.join(tmp, 'notes.md'); File.write(notes, body)
        run('gh', 'release', 'create', tag, *paths.values, '--repo', REPO, '--target', commit, '--draft', '--title', "DropDrive #{options[:version]} · Mac + Windows", '--notes-file', notes)
      end
      puts "Draft #{tag} staged with BOTH platforms; no user update published."
      return
    end
    # Draft tags need not exist as Git refs yet. Enumerate authenticated drafts
    # instead of the published-release-by-tag endpoint.
    releases = JSON.parse(run('gh', 'api', "repos/#{REPO}/releases?per_page=100", '--paginate', '--slurp')).flatten
    matches = releases.select { |r| r['tag_name'] == tag }
    require!(matches.length == 1, 'Expected exactly one draft for this tag')
    release = matches.first
    require!(release['draft'] && !release['prerelease'] && release['target_commitish'] == commit, 'Only this commit’s complete draft may be published')
    assets = release.fetch('assets')
    require!(assets.map { |a| a['name'] }.sort == paths.keys.sort, 'Remote draft assets differ from verified local pair')
    # Verify what users will download, not only the local staging directory.
    Dir.mktmpdir('dropdrive-paired-verify-') do |tmp|
      run('gh', 'release', 'download', tag, '--repo', REPO, '--dir', tmp)
      paths.each { |name, path| require!(Digest::SHA256.file(File.join(tmp, name)).hexdigest == Digest::SHA256.file(path).hexdigest, "Remote draft differs: #{name}") }
      require!(release['body'].to_s.strip == body.strip, 'Draft notes differ; review before publishing')
      run('gh', 'api', '--method', 'PATCH', "repos/#{REPO}/releases/#{release.fetch('id')}", '-F', 'draft=false', '-f', 'make_latest=true')
    end
    puts "Published #{tag}: Mac and Windows became available in the same release."
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    PairedRelease.main(ARGV)
  rescue StandardError => e
    warn "Release blocked: #{e.message}"
    exit 1
  end
end
