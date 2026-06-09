# Google Play App Content Declarations

Last updated: May 12, 2026

Use this file when filling out **Play Console -> Policy and programs -> App content** for Memoria.

## Set Privacy Policy

Recommended selection:

- Provide a public Privacy Policy URL.
- Use the published version of `docs/privacy-policy.md`.
- The URL must be active, publicly accessible, non-geofenced, not a PDF, and non-editable by users.
- Add an in-app privacy policy link before release if possible.

Memoria notes:

- Mention photo library access, camera access, local custom filter storage, exports, and advertising SDKs.
- Keep the Privacy Policy consistent with Data safety answers.

## App Access

Recommended selection:

- If all app functionality is available without login, membership, location restriction, or special credentials: choose that no special access is required.
- If a later version gates features behind sign-in, subscription, tester codes, region locks, or membership, provide reviewer instructions and credentials.

Memoria notes:

- Current app has no account login.
- Photo picker permissions are device permissions, not review access restrictions.

## Ads

Recommended selection:

- Choose **Yes, my app contains ads** if AdMob or any ad SDK can show banner, interstitial, rewarded, native, house, or promotional ads in the release build.
- Choose **No** only if all ad SDK display paths are removed or disabled for the release build.

Memoria notes:

- `google_mobile_ads` and monetization code are present.
- If ads remain integrated, declare ads and ensure ad content rating settings match the app content rating.

## Content Rating

Recommended selection:

- Complete the questionnaire based on the actual app content.
- Memoria is a photo editor and should normally answer "none" or equivalent for violence, sexual content, gambling, drugs, hate, and similar restricted content.
- If users can import any photo, answer based on app-provided content and features, not private user gallery content, unless the app publicly shares or distributes user content.

Memoria notes:

- No social sharing feed, chat, gambling, health advice, or user-generated public content is currently present.
- Camera/photo access should be disclosed through permissions and privacy forms.

## Target Audience

Recommended selection:

- Recommended target audience: adults or general users, not specifically children.
- Do not include children unless the app is deliberately designed for children and all Families policy requirements are met.

Memoria notes:

- Because ads may be present and the app is not a child-focused product, avoid selecting child age groups unless the product direction changes.

## Data Safety

Recommended approach:

- Declare all data collected or shared by the app and by third-party SDKs.
- Include advertising SDK behavior if ads are enabled.
- Include photos/images only if they are collected from the device or shared off-device. If photo processing stays entirely local and photos are not transmitted, declare that accurately.
- Declare security practices, data deletion, and whether collection is optional or required.

Memoria notes:

- Photos are selected for editing and filter generation.
- Generated filters, LUTs, thumbnails, and metadata are stored locally.
- AdMob may collect or share advertising identifiers, device identifiers, usage data, diagnostics, approximate location, and related ad data depending on SDK configuration.
- No account creation currently exists.

## Government Apps

Recommended selection:

- Memoria is not a government app and does not communicate government information.

Memoria notes:

- Select the equivalent of "No" unless the app later claims affiliation with or provides services for a government agency.

## Financial Features

Recommended selection:

- Memoria does not provide financial features.

Memoria notes:

- Select "My app doesn't provide any financial features."
- If subscriptions, paid downloads, or in-app purchases are added, those are not necessarily "financial services" features, but still review the declaration text carefully.

## Health

Recommended selection:

- Memoria does not provide health features.

Memoria notes:

- Select "My app doesn't provide any health features."
- Do not market camera/photo features as diagnosis, treatment, medical measurement, skin analysis, mental health, fitness, or wellness guidance unless the full health policy requirements are implemented.

## Official References

- Prepare app for review / App content: https://support.google.com/googleplay/android-developer/answer/9859455
- App access, Ads, Target audience overview: https://support.google.com/googleplay/android-developer/answer/9859455
- Ads policy: https://support.google.com/googleplay/android-developer/answer/9857753
- Content rating and target audience requirements: https://support.google.com/googleplay/android-developer/answer/9859655
- Data safety: https://support.google.com/googleplay/android-developer/answer/10787469
- Developer Program Policy / Privacy Policy: https://support.google.com/googleplay/android-developer/answer/16329168
- Government apps: https://support.google.com/googleplay/android-developer/answer/9514050
- Financial features declaration: https://support.google.com/googleplay/android-developer/answer/13849271
- Financial Services policy: https://support.google.com/googleplay/android-developer/answer/16322411
- Health apps declaration: https://support.google.com/googleplay/android-developer/answer/14738291
- Health Content and Services: https://support.google.com/googleplay/android-developer/answer/12261419
