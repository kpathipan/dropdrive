require 'json'
require 'digest'
require 'open3'
root = File.expand_path('..', __dir__)
Dir.chdir(root) do
  version = ARGV.fetch(0)
  abort 'Invalid version' unless version.match?(/\A\d+\.\d+\.\d+\z/)
  dmg = "DropDrive-v#{version}.dmg"
  app = 'build-adhoc/DerivedData/Build/Products/Release/DropDrive.app'
  abort 'Signed app is missing' unless File.directory?(app)
  abort 'Signature verification failed' unless system('codesign', '--verify', '--deep', '--strict', app)
  _, signature, status = Open3.capture3('codesign', '-dvvv', app)
  abort 'Stable timestamped/hardened signature is required' unless status.success? && signature.include?('TeamIdentifier=') && !signature.include?('TeamIdentifier=not set') && signature.include?('Timestamp=') && signature.include?('runtime')
  commit, status = Open3.capture2('git', 'rev-parse', 'HEAD')
  abort 'Could not resolve commit' unless status.success?
  receipt = { schema: 1, platform: 'mac', version: version, commit: commit.strip,
    contract_sha256: Digest::SHA256.file('packaging/parity-contract.json').hexdigest,
    checks: %w[regressions performance keychain offline-engine media-fixtures signed-build],
    files: [{ name: dmg, sha256: Digest::SHA256.file(File.join('dist', dmg)).hexdigest }] }
  File.write('dist/mac-build.json', JSON.pretty_generate(receipt))
end
