require 'minitest/autorun'
require_relative 'paired-release'

class PairedReleaseTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir('dropdrive-pair-test-')
    @mac = File.join(@tmp, 'mac'); @win = File.join(@tmp, 'windows')
    Dir.mkdir(@mac); Dir.mkdir(@win)
    @version = '6.25.0'; @commit = 'a' * 40
    @contract = File.join(@tmp, 'contract.json')
    write(@contract, { features: ['drive', 'video'] })
    hash = Digest::SHA256.file(@contract).hexdigest
    @evidence = File.join(@tmp, 'evidence.json')
    write(@evidence, { version: @version, commit: @commit, contract_sha256: hash,
      features: %w[drive video].to_h { |f| [f, %w[mac windows].to_h { |p| [p, { status: 'pass', evidence: 'local fixture for validator only' }] }] } })
    dmg = "DropDrive-v#{@version}.dmg"; File.write(File.join(@mac, dmg), 'fixture DMG')
    nupkg = "com.dropdrive.windows-#{@version}-full.nupkg"
    [nupkg, 'com.dropdrive.windows-win-Setup.exe', 'com.dropdrive.windows-win-Portable.zip', 'RELEASES'].each { |n| File.write(File.join(@win, n), 'fixture package') }
    pkg = File.join(@win, nupkg)
    write(File.join(@win, 'releases.win.json'), { Assets: [{ PackageId: 'com.dropdrive.windows', Version: @version, Type: 'Full', FileName: nupkg,
      Size: File.size(pkg), SHA1: Digest::SHA1.file(pkg).hexdigest, SHA256: Digest::SHA256.file(pkg).hexdigest }] })
    [[@mac, 'mac', %w[regressions performance keychain offline-engine media-fixtures signed-build]],
     [@win, 'windows', %w[core-ui native-shell packaged-startup installed-upgrade]]].each do |dir, platform, checks|
      write(File.join(dir, "#{platform}-build.json"), { schema: 1, platform: platform, version: @version, commit: @commit,
        contract_sha256: hash, checks: checks, files: Dir.children(dir).map { |n| { name: n, sha256: Digest::SHA256.file(File.join(dir, n)).hexdigest } } })
    end
  end
  def teardown
    FileUtils.remove_entry(@tmp) if @tmp
  end
  def write(path, value); File.write(path, JSON.generate(value)); end
  def change(path); data = PairedRelease.json(path); yield data; write(path, data); end
  def verify
    PairedRelease.validate(@version, @mac, @win, @evidence, commit: @commit, contract_path: @contract)
  end
  def test_complete_pair
    assert_equal 6, verify.first.size
  end
  def test_mismatched_version
    change(File.join(@win, 'windows-build.json')) { |d| d['version'] = '0.7.0' }
    assert_raises(RuntimeError) { verify }
  end
  def test_mismatched_commit
    change(File.join(@mac, 'mac-build.json')) { |d| d['commit'] = 'b' * 40 }
    assert_raises(RuntimeError) { verify }
  end
  def test_missing_other_platform
    File.unlink(File.join(@win, 'com.dropdrive.windows-win-Setup.exe'))
    assert_raises(RuntimeError) { verify }
  end
  def test_modified_payload
    File.write(File.join(@mac, "DropDrive-v#{@version}.dmg"), 'changed bytes')
    assert_raises(RuntimeError) { verify }
  end
  def test_unverified_feature
    change(@evidence) { |d| d['features']['video']['windows']['status'] = 'unavailable' }
    assert_match(/Parity NOT verified/, assert_raises(RuntimeError) { verify }.message)
  end
  def test_stale_contract
    write(@contract, { features: %w[drive video more] })
    assert_raises(RuntimeError) { verify }
  end
  def test_missing_test
    change(File.join(@win, 'windows-build.json')) { |d| d['checks'].delete('installed-upgrade') }
    assert_raises(RuntimeError) { verify }
  end
  def test_feed_references_unshipped_package
    path = File.join(@win, 'releases.win.json')
    change(path) { |d| d['Assets'][0]['FileName'] = 'missing.nupkg' }
    change(File.join(@win, 'windows-build.json')) { |d| d['files'].find { |f| f['name'] == 'releases.win.json' }['sha256'] = Digest::SHA256.file(path).hexdigest }
    assert_raises(RuntimeError) { verify }
  end
end
