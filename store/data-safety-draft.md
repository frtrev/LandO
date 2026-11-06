# LandO Data safety worksheet

This is a developer review worksheet for the current build, not an automatically submitted declaration. Recheck account/provider terms and the latest SDK disclosures when filling in Play Console. Do not answer “no data collected”: Maps/Places SDKs, optional cloud AI/search and voluntary reports transmit data off device.

| Data | Current app behavior | Proposed purpose / optionality to review |
|---|---|---|
| Precise / approximate location | Foreground GPS permission; map viewport and address search context; coordinates can appear in cloud AI context and search queries | App functionality. GPS permission optional; cloud AI and research optional. Disclose relevant SDK collection even if GPS is denied. |
| Other user-generated content / messages | Cloud questions, recent chat, names/descriptions and property measurements; comments and opted-in selected answer in reports | App functionality and support/safety. Optional. Cloud provider, search service and FormSubmit/email retention apply; do not label this all ephemeral. |
| App interactions / diagnostics | Maps/Places SDK request metadata, SDK failures and performance information | Functionality, diagnostics and SDK analytics, as documented by Google. Some SDK data is collected automatically. |
| Device or other IDs | Google Maps Platform SDK-specific identifier and device/network metadata | SDK analytics/operation; review Google's disclosure for the exact SDK versions. No advertising ID integration or developer analytics SDK was added. |
| User-provided account credentials (review category) | AI API keys stay in secure storage and are transmitted only to the selected provider for request authentication | Optional cloud functionality. Review whether account/User ID categories apply under the current Console definitions and provider terms. Never include keys in reports or backups. |
| Files | A user explicitly exports/shares a backup or imports a chosen file | User-directed transfer. No broad storage permission; user manages exported copies. Review the user-initiated transfer exception. |

For “collected” versus “shared”, include SDK behavior and all enabled optional features. A service-provider or user-initiated-transfer exception must actually apply; do not assume all AI providers are exempt from sharing just because the user supplies an API key. Where a provider can use content for its own purposes, review that separately. The app-level consent explains what is sent before a first cloud request or local internet research request; it can be declined. Restore resets these sharing approvals.

All app network destinations are HTTPS. Backups are readable/unencrypted files controlled by the user. No LandO login/account exists, so an account-deletion endpoint is not applicable; answer the Console questions accordingly. Properties/conversations/keys/model weights can be deleted locally, Android storage can be cleared, and support can handle identifiable report-deletion requests at ftrevino@yahoo.com. Do not promise deletion of data independently retained by AI/search/Maps providers.

There are no in-app ads, payments, contacts access, microphone, camera, broad photo/library access, background location or developer-operated analytics in the current app. Review the final merged manifest and SDK inventory in build/play-store/validation.json, not just the source manifest. The voluntary reporting form has no user email field; do not invent a mandatory email collection field in the declaration.

Primary references (reviewed November 5, 2026):
- Google User Data policy: https://support.google.com/googleplay/android-developer/answer/10144311
- Data safety guidance: https://support.google.com/googleplay/android-developer/answer/10787469
- Maps SDK disclosure: https://developers.google.com/maps/documentation/android-sdk/play-data-disclosure
- Places SDK disclosure: https://developers.google.com/maps/documentation/places/android-sdk/play-data-disclosure
- AI-generated content policy: https://support.google.com/googleplay/android-developer/answer/13985936
- Account deletion applicability: https://support.google.com/googleplay/android-developer/answer/13327111
