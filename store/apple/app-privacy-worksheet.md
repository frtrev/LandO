# LandO App Store privacy worksheet

Review against the exact distribution build and current provider account terms before completing App Store Connect. This is not a submitted declaration. The local-only property database does not mean “Data Not Collected”: Maps/Places, optional cloud AI, research and voluntary reports send data off device.

The archive checker writes the actual SDK privacy manifests to `build/app-store/archive-validation.json`. Xcode Organizer can generate an aggregate Privacy Report. A manifest does not replace the App Store privacy questionnaire, provider retention review or informed consent.

| Category to review | Actual use | Purposes / linkage to assess |
| --- | --- | --- |
| Precise / coarse location | Foreground location centers the map; map/search context and optional AI context can contain precise property coordinates. | Functionality; Maps/Places SDK analytics as declared by those SDKs. GPS is optional, but SDK behavior still applies when permission is denied. Cloud API accounts and precise property data can link submitted content to a person. |
| Other user content | Questions, recent chat, property names/descriptions and app-calculated context go to the selected cloud provider after explicit consent. | Optional app functionality. Do not assume transient processing: provider retention depends on the user's account and product terms. |
| Customer support | Voluntary report reasons/comments and opted-in selected answer go to FormSubmit/email. Support emails include the sender's email. | Support/functionality. Assess the optional-feedback exception against Apple's complete conditions; it does not automatically exempt all reports. |
| Search history | Address queries to Places, research queries to provider search or DuckDuckGo. | Functionality; SDK analytics where declared. Queries can include property/location context. |
| Identifiers | Maps/Places SDK identifiers and Google account/app context; cloud API credentials identify the user's provider account. | Include SDK-declared Device ID/User ID/other data where applicable. API keys are in Keychain, never LandO backups/reports. No advertising identifier or ATT integration is present. |
| Usage data / diagnostics / other data | Maps/Places SDK interactions, performance/crash information and other SDK operational data. | SDK analytics/functionality. Inspect each SDK's current manifest, including linked flags; do not claim no analytics across all third parties. |
| Physical address / other categories | Users can put addresses and arbitrary content in questions or property descriptions shared with AI. | Assess under Apple's definitions. Do not preselect “not linked” solely because LandO has no account. |

Current first-party manifest conservatively declares optional app functionality collection of precise/coarse location, other user content, support and search history as linked, without tracking. SDK manifests add their own declarations, including identifiers/analytics. No ads, cross-app advertising profiles or tracking domains are configured. Reassess ATT if future SDKs introduce Apple's definition of tracking; do not add a permission prompt just for ordinary location or AI sharing.

Required-reason API declaration at app level: FileTimestamp / C617.1 for file metadata used to verify and reuse the model inside the app container. Flutter, the llama runtime, Maps/Places and other plugins have separate manifests in the archive. Do not remove vendor manifests or invent unrelated reasons to silence warnings.

No LandO account is created, so there is no account deletion workflow to provide. Users can delete properties/conversations, keys and model weights. On iOS, deleting the app removes its container but Keychain data can survive reinstalling; remove keys in app settings first. Offloading retains app data. Device backups and user-exported files are independently retained; downloaded model weights are excluded from iCloud device backups. Support handles identifiable report/support deletion requests at ftrevino@yahoo.com, subject to security/legal retention. Do not promise deletion from independent third-party providers.

Official references, checked November 6, 2026:
- https://developer.apple.com/app-store/app-privacy-details/
- https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
- https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- https://developers.google.com/maps/documentation/ios-sdk/apple-privacy-policy
- https://developers.google.com/maps/documentation/places/ios-sdk/apple-privacy-policy
- https://developer.apple.com/app-store/review/guidelines/#privacy
