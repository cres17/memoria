# App Store Privacy and Review Notes

Last updated: May 12, 2026

Use this file when filling out App Store Connect metadata for Memoria.

## Privacy Policy URL

Apple requires a Privacy Policy URL for all apps. Publish `docs/privacy-policy.md` as a public web page and enter that URL in App Store Connect.

Before creating a signed release tag, configure these GitHub repository variables with the same reviewed values: `PRIVACY_POLICY_URL`, `PRIVACY_CONTACT_EMAIL`, and `ADVERTISING_RELEASE_MODE=disabled`. The signed iOS workflow fails before codesigning if any value is absent or inconsistent with the ad-free v1 policy.

Path:

- App Store Connect -> Apps -> Memoria -> App Privacy
- Edit Privacy Policy URL

## App Privacy Details

Apple requires app-level privacy answers that include both first-party collection and third-party partner SDK collection.

Memoria notes:

- If photos remain fully local and are not transmitted, answer accordingly.
- If AdMob is enabled, include data collected by Google Mobile Ads according to the SDK's current data practices.
- If analytics or crash reporting SDKs are added, update the answers before release.

## Age Rating

Path:

- App Store Connect -> App Information -> Age Rating

Memoria notes:

- Photo editing app with no public social feed should generally have low-risk content answers.
- Do not claim medical, treatment, gambling, or unrestricted web content features unless such features exist.

## Health or Medical Declarations

Memoria is not a health or medical app. Do not include medical claims in screenshots, descriptions, or metadata.

If future features analyze skin, body, mental health, medical images, or similar health-related data, update this file and complete the applicable Apple declarations before release.

## Official References

- App information, Privacy Policy URL: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- App privacy reference: https://developer.apple.com/help/app-store-connect/reference/app-privacy
- Manage app privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- Set an app age rating: https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating
- Age rating values and definitions: https://developer.apple.com/help/app-store-connect/reference/age-ratings-values-and-definitions
