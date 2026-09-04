# Repository ownership

- This repository owns the standalone ARMSX3 application, reusable PS3 core,
  public native ABI, renderer, JIT, NETISO transport, tests and standalone docs.
- EmuHub application adapters, authentication, library/scanner integration,
  server/admin UI and Docker configuration belong only in their EmuHub client or
  server repositories. Clients share EmuHub umbrella branding; ARMSX3 is an
  affiliated core with independent runtime branding.
  Do not copy those modules here, add a reverse dependency, or bulk-sync trees.
- Shared controller media is explicitly allowed by the owner. Preserve source
  attribution and native dimensions. Standalone runtime branding is ARMSX3;
  an integration app supplies its own presentation outside this repository.
- A reusable provider interface/ABI may be implemented here without importing
  a consuming application's code. Application-specific provider implementation,
  deployment policy and planning belong in that application's repository.
- Historical test notes are evidence, not permission to import integration code.
  Never rewrite published history to remove old branding or attribution.
- Read platforms/ios/TEST_STATUS.md and CONTROLLER_LAYOUT.md before UI changes.
  Stage explicit paths only; do not stage other work in progress, especially the
  native Metal renderer. Shell-only IPA builds must use the accepted-core script.
- Keep the 8-GB Mac resource ceiling: bounded reads, one build worker, no broad
  log/image dumps. Update exact test/package status without claiming device proof.
- Use the requested public commit identity: gr33k <gr33k420@gmail.com>.
