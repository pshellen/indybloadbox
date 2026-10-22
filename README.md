# FSCinema Menu Boards for info-beamer Hosted

Live, resilient menu-board package for the schema-version-1 FSCinema manifest. It supports `combo`, `alacarte`, `full`, and `hotfoods` screens at 3840×1080 dual-HD horizontal, 2160×3840 4K vertical, 1920×1080 HD horizontal, and 3840×2160 4K horizontal.

## Raspberry Pi compatibility

- **Raspberry Pi 3:** Compatible for 1920×1080 playback. Use H.264 advertisement videos no larger than 1920×1080.
- **Raspberry Pi 4:** Compatible with 1920×1080, 3840×1080 dual-HD, and tested 4K-capable display configurations.
- **Raspberry Pi 5:** Compatible and recommended for dual-HD, 4K, and more demanding video playback.

Actual maximum output resolution depends on the info-beamer OS release, HDMI configuration, connected display, and video codec. Validate dual-display and 4K modes on the intended hardware before deployment.

The service sends `If-None-Match`, accepts empty 304 responses, validates new JSON before publishing it, atomically updates player state, caches media by URL plus content version, and retains the last valid manifest when a refresh fails. The last-known-good manifest and its media are also copied to info-beamer's persistent `SCRATCH` storage and restored before the first network request after a restart. Combo images use each combo's `image_url` and appear in the image area above the name, description, and price. A neutral placeholder is used when `image_url` is null or empty.

Combo `day_prices` are resolved on the device using the location timezone and the endpoint's Sunday=0 through Saturday=6 `day_of_week` convention. The matching price is recalculated on every refresh, including HTTP 304 responses and offline cached-state refreshes, while the normal `display_price` remains the fallback.

## Hosted import

1. In info-beamer Hosted, open **Packages**, choose **Import package**, and upload `fscinema-menu-board.zip` (or import the repository URL if this directory is hosted in Git).
2. Review the requested network permission. It is required for the manifest endpoint and public media URLs.
3. Create a setup from **FSCinema Menu Boards**.
4. Configure the endpoint, Wellington location ID, screen ID, bearer token, and display profile. Keep refresh at 600 seconds to match `Cache-Control: private, max-age=600, must-revalidate`.
5. Save, assign the setup to one test device, and wait for synchronization.

The token field is visually masked in Hosted but is ultimately delivered to the device in `config.json`; use a dedicated, read-only player token and rotate it if exposed. Do not use an admin/service-role credential.

## Configuration

- **Screen:** Use `combo`, `alacarte`, `full`, or `hotfoods`; this becomes the endpoint's `screen_id` query value. Only locations with a Hot Foods screen configured by the web app will return `hotfoods` data.
- **Location:** Select one of the 20 configured FSCinema locations from the dropdown, or choose Custom location ID and enter another location UUID. Existing setups using only the location ID field remain compatible.
- **Display profile:** Must match the intended canvas. The player letterboxes safely if the physical output differs.
- **Output rotation:** Rotates the entire composed menu clockwise by 90°, 180°, or 270° and automatically fits the rotated canvas to the physical output. Existing setups default to no rotation.
- **Playback mode:** `Configured screen` renders the selected manifest normally. `Alternate combo / a la carte` uses a `full` manifest and switches between full-screen combo and à-la-carte pages; configure `screen_id=full` and typically use 1920×1080. `Alternate combo / Hot Foods` automatically fetches the `combo` and `hotfoods` manifests. `Alternate a la carte / Hot Foods` does the same with the `alacarte` and `hotfoods` manifests. Both Hot Foods modes ignore the configured Screen value and use the page duration for rotation timing.
- **Always hide Hot Foods:** Removes Hot Foods cards from a-la-carte and full layouts and suppresses the Hot Foods half of either Hot Foods rotation mode. Defaults to off so existing setups are unchanged.
- **Page duration:** Number of seconds each page remains visible in alternating mode; defaults to 25 seconds.
- **Combo upgrades placement:** When a Combo Upgrade category is present, place it at the bottom of Popcorn, Snacks, Refreshing Drinks, or on a separate card. Defaults to Popcorn; a missing target falls back to a separate card.
- **Combo font size:** Independently scales combo names, descriptions, and prices from 75% to 250%; defaults to 100%.
- **A la carte font size:** Independently scales category headings, item names, and prices from 75% to 250%; defaults to 100%.
- **Refreshing Drinks title font size:** Independently scales only the combined Refreshing Drinks card title from 75% to 250%; defaults to 100%. Existing configurations without this setting fall back to the A la carte font size.
- **Refreshing Drinks font size:** Independently scales the group headings, item names, and prices in the Refreshing Drinks card from 75% to 250%; defaults to 100%. It does not affect the card title. Existing configurations without this setting fall back to the A la carte font size.
- **Hot Foods font size:** Independently scales the dedicated Hot Foods heading, item names, and prices from 75% to 250%; defaults to 100%.
- **Sales tax font size:** Independently scales the tax disclaimer from 50% to 250%; defaults to 100%.

Values above 125% are provided for on-device assessment and may cause clipping or vertical overlap on dense menus. Increase each screen type gradually and verify the complete rotation before rollout.
- **Show advertisements:** Downloads and rotates active, in-date advertising media in the advertisement region. If no valid advertisement is available, the region collapses and the menu uses the available space.
- **Theme / takeover overlay:** Select an uploaded transparent PNG to draw above the entire composed screen. Use it for holiday borders, branded corner art, rating callouts, or full movie takeovers. The included transparent default keeps existing setups unchanged.
- **Overlay fit:** `Stretch` maps the PNG exactly to the configured display profile and is recommended for canvas-matched artwork. `Contain` preserves the whole image and may leave uncovered edges. `Cover / crop` fills the canvas while preserving aspect ratio.
- **Overlay opacity:** Controls the overlay from fully hidden (0%) to its original PNG alpha (100%). Transparent pixels in the source remain transparent.
- **Debug status:** Shows LIVE/STALE and the current manifest version in the upper-left corner.

When a refresh fails after at least one successful sync, the last saved menu remains on screen and a small Flagship Cinemas Premium Support logo appears in the lower-right corner. The indicator disappears automatically after connectivity recovers.

The endpoint's `screen.orientation` and source dimensions are retained as data, while the explicit Hosted display profile controls the physical composition. Use **Output rotation** when the player must rotate the complete rendered menu instead of relying on device or TV rotation.

## Hot Foods screen

Select **Hot Foods** with the 1920×1080 display profile for the dedicated split layout. The left half shows the available Hot Food items and tax disclaimer; the right half rotates images and H.264 videos from the manifest's `hotfoods_media` playlist using the local device cache. `hotfoods_media_urls` is supported as a URL-only compatibility fallback. General `advertisements` are not used by this layout. If no playable Hot Foods media exists, the right half remains black with a small “No media available” message.

The service honors the web app's `schedule` records using each location's timezone. `hide_start_time` and `hide_end_time` can cross midnight (for example, Pottstown hides Hot Food from 10:05 PM until 10:30 AM). Schedule state is recalculated locally at least once per minute without redownloading the manifest or media. Outside the display window, prices and items are replaced by “Currently unavailable.”

## Rollout

1. Verify the test device reports LIVE and the expected manifest version.
2. Confirm all menu prices and category/combo order against the source system.
3. Add one combo `image_url` in the source and verify the image appears above that combo's price card after the next refresh.
4. Disconnect networking for longer than one refresh interval and confirm the last menu remains visible (STALE when debug is enabled).
5. Reconnect, confirm recovery, then assign the setup to a small pilot group.
6. Roll out by screen type in batches. Keep the previous setup assigned to no devices but available during the observation window.

For 4K output, use hardware and an info-beamer OS version with the required 4K image/video capabilities. Validate the exact HDMI mode and rotation on the production display before broad deployment.

## Rollback

1. Reassign affected devices to the previously known-good setup in Hosted.
2. Wait for device synchronization and verify the live preview/device screenshot.
3. If the player does not switch, reboot only the affected device from Hosted and recheck.
4. Keep the failed package version and logs for diagnosis; do not overwrite the known-good package. Rotate the player token only if credentials may have been exposed.

Cached state is scoped to the setup/package instance. A newly attached setup can start with an empty cache and will display “Waiting for menu data…” until its first successful request.

## Local verification

Run `python3 -m unittest discover -s tests -v`. For visual testing, run `python3 -m http.server 8765` and open `http://127.0.0.1:8765/preview/`. The committed fixtures are the verbatim Wellington responses supplied on 2026-09-03 and contain no credentials.

The package includes Poppins Bold under the SIL Open Font License; see `OFL.txt`.

## Overlay artwork

Create the PNG at the same pixel dimensions and orientation as the selected display profile whenever possible. Keep menu-readable areas transparent and place decorative or takeover artwork only where intended. Because the overlay is the final rendering layer, it also appears above advertisements, debug status, and the offline indicator. Swap or remove the selected asset in Hosted without rebuilding the package.

## Version 1.8.4

Adds an **Always hide Hot Foods** checkbox. When enabled, Hot Foods categories are filtered from a-la-carte and full menus, Hot Foods rotation is suppressed, and a directly configured Hot Foods screen displays an unavailable message instead of menu content or media.

## Version 1.8.3

Allows `Hot Food` and `Hot Foods` categories returned in an a-la-carte or full manifest to render as normal menu cards. Dedicated Hot Foods playback and rotation continue to use the separate Hot Foods screen data.

## Version 1.8.2

In portrait layouts, top-aligns advertisements at their natural aspect ratio and starts the combo grid immediately below the actual rendered banner height. This gives the combo cards the unused letterbox space while preserving established horizontal advertisement rendering.

## Version 1.8.1

Preserves advertisement image and video aspect ratios in portrait layouts, preventing landscape artwork from being stretched into the vertical advertisement region.

## Version 1.8.0

Adds a Hosted **Output rotation** setting for no rotation, 90° clockwise, 180°, and 270° clockwise. The complete composed canvas is rotated and automatically fitted to the physical output, including menus, advertising, overlays, offline status, and debug text.

## Version 1.7.2

Restores conditional HTTP caching for the two feeds used by Combo/Hot Foods and A la carte/Hot Foods rotation modes, avoiding redundant manifest processing and media-cache scans when a screen has not changed.

## Version 1.7.1

Adds an `Alternate a la carte / Hot Foods` playback mode.

## Version 1.7.0

Adds an `Alternate combo / Hot Foods` playback mode that fetches both screen-specific manifests and rotates between them using the configured page duration.

## Version 1.6.1

Treats JSON `null` text values as blank so optional fields such as the tax disclaimer never render as `userdata: null`.

## Version 1.6.0

Separates the Refreshing Drinks card title scaling from its group headings, item names, and prices by providing two independent controls.

## Version 1.5.1

Reduces the top and bottom margins of the a-la-carte card grid to provide more vertical room for increased font scaling while retaining the existing horizontal spacing.

## Version 1.5.0

Adds an independent font-size control for the complete Refreshing Drinks section, including its heading, drink groups, items, prices, and any Combo Upgrades placed in that section.

## Version 1.4.0

Uses the dedicated `hotfoods_media` playlist on Hot Foods screens, with support for `hotfoods_media_urls` as a fallback, and accepts screen-specific manifests that omit `combos`.

## Version 1.3.0

Adds an optional 4K-capable transparent PNG overlay with configurable stretch, contain, or cover placement and opacity for holiday themes and movie takeovers.

## Version 1.2.0

Adds the scheduled Hot Foods split screen with cached image/video playback, location-timezone special-day pricing, and configurable Combo Upgrade placement, along with Python 2.7 service compatibility, schema validation, ETag revalidation, offline retention, responsive layouts, advertisement rotation, and combo image slots.
