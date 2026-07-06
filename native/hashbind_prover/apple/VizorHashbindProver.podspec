# Local development pod vendoring the prebuilt on-device hashbind prover
# (see native/hashbind_prover/README.md). The xcframework is produced by
# scripts/build-hashbind-prover.sh and intentionally not committed; the
# Podfiles skip this pod with a warning when it is absent.
Pod::Spec.new do |s|
  s.name                 = 'VizorHashbindProver'
  s.version              = '0.1.0'
  s.summary              = 'On-device ProveKit hashbind prover for zwap b2z/z2b swaps.'
  s.description          = 'Prebuilt Rust cdylib wrapping provekit-ffi at the ' \
                           'solver-pinned rev so the spend-auth scalar never leaves the device.'
  s.homepage             = 'https://github.com/chainapsis/vizor-wallet'
  s.license              = { :type => 'Apache-2.0', :file => '../../../LICENSE' }
  s.author               = 'Vizor'
  s.source               = { :path => '.' }
  s.vendored_frameworks  = 'VizorHashbindProver.xcframework'
  s.ios.deployment_target  = '15.0'
  s.osx.deployment_target  = '11.0'
end
