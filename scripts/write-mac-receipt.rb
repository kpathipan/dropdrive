require 'json'
require 'digest'
require 'open3'
require 'tmpdir'
root = File.expand_path('..', __dir__)
Dir.chdir(root) do
  version = ARGV.fetch(0)
  expected_commit = ARGV.fetch(1)
  abort 'Invalid version' unless version.match?(/\A\d+\.\d+\.\d+\z/)
  dmg = "DropDrive-v#{version}.dmg"
  commit, status = Open3.capture2('git', 'rev-parse', 'HEAD')
  abort 'Source commit changed during preparation' unless status.success? && commit.strip == expected_commit
  changes, status = Open3.capture2('git', 'status', '--porcelain')
  abort 'Source changed during preparation' unless status.success? && changes.strip.empty?
  dmg_path = File.expand_path(File.join('dist', dmg))
  abort 'Disk image verification failed' unless system('hdiutil', 'verify', dmg_path)
  packaged_hash = Digest::SHA256.file(dmg_path).hexdigest
  # build-dmg removes its scratch app. Inspect the shipped app, not a stale
  # build directory, and never install or register it on the signing machine.
  mount = Dir.mktmpdir('dropdrive-receipt-')
  mounted = false
  begin
    abort 'Could not mount disk image' unless system('hdiutil', 'attach', dmg_path, '-readonly', '-nobrowse', '-noautoopen', '-mountpoint', mount)
    mounted = true
    app = File.join(mount, 'DropDrive.app')
    abort 'Signed app is missing from disk image' unless File.directory?(app)
    abort 'Signature verification failed' unless system('codesign', '--verify', '--deep', '--strict', app)
    _, signature, status = Open3.capture3('codesign', '-dvvv', app)
    abort 'Stable timestamped/hardened signature is required' unless status.success? && signature.include?('TeamIdentifier=') && !signature.include?('TeamIdentifier=not set') && signature.include?('Timestamp=') && signature.include?('runtime')
    plist, status = Open3.capture2('plutil', '-convert', 'json', '-o', '-', File.join(app, 'Contents', 'Info.plist'))
    abort 'Could not read packaged version' unless status.success?
    info = JSON.parse(plist)
    abort 'Packaged app identity/version does not match' unless info['CFBundleIdentifier'] == 'com.dropdrive.DropDrive' && info['CFBundleShortVersionString'] == version
  ensure
    detached = !mounted || system('hdiutil', 'detach', mount)
    Dir.rmdir(mount) if detached && File.directory?(mount)
    abort "Could not unmount receipt inspection at #{mount}" unless detached
  end
  final_commit, commit_status = Open3.capture2('git', 'rev-parse', 'HEAD')
  final_changes, changes_status = Open3.capture2('git', 'status', '--porcelain')
  abort 'Source changed during artifact inspection' unless commit_status.success? && changes_status.success? && final_commit.strip == expected_commit && final_changes.strip.empty?
  abort 'Disk image changed during inspection' unless Digest::SHA256.file(dmg_path).hexdigest == packaged_hash
  receipt = { schema: 1, platform: 'mac', version: version, commit: commit.strip,
    contract_sha256: Digest::SHA256.file('packaging/parity-contract.json').hexdigest,
    checks: %w[regressions performance keychain offline-engine media-fixtures signed-build],
    files: [{ name: dmg, sha256: packaged_hash }] }
  File.write('dist/mac-build.json', JSON.pretty_generate(receipt))
end
