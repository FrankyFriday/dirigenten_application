# Android release and in-app updates

## Release flow

Both Android release workflows build and sign an APK, upload it to the
Nextcloud `releases` folder, create a public read-only share link, and register
the release with `POST https://ws.notenserver.duckdns.org/api/releases`.
The noten-server stores the release and sends `release_announce` to connected
clients registered for that app. On connection, clients also receive the
currently published release.

The apps accept only a newer release with the expected Android package name,
version, and signing certificate. The verified APK is opened with Android's
package installer. Android may require the user to allow this app to install
unknown apps in system settings.

Actions, Octopus, and client registration retain the IDs
`dirigenten_application` and `musiker_application`. The server emits
`dirigenten_app` and `musiker_app` in release announcements; clients accept both
the long and canonical IDs.

## Publishing a release

- Push a `vX.Y.Z` tag, or run **Android Release** manually and enter `X.Y.Z`.
- The Nextcloud account must be able to upload files and create public shares.
  Public link sharing must be enabled. The APK URL is not published to the
  server until Nextcloud returns a valid HTTPS share link.
- Configure these GitHub Actions secrets in **both** app repositories:
  `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`,
  `NC_USER`, `NC_PASS`, and `NOTEN_SERVER_API_KEY`.
  `NOTEN_SERVER_API_KEY` must match the `API_KEY` configured on the running
  noten-server. Existing Octopus deployment also requires `OCTOPUS_API_KEY`
  and `OCTOPUS_SPACE`.
- `KEYSTORE_BASE64` must contain the base64-encoded JKS used to sign the
  already-installed version of that app. Keep the keystore and passwords
  backed up securely; changing the signing key prevents Android from installing
  an update over existing installations.

The workflow validates all required signing secrets, decodes and verifies the
keystore alias, and fails before building if the keystore or its properties
are missing. The keystore and `key.properties` are generated only in the CI
workspace and are not included in the APK. The bundled
`assets/.env.example` contains only the public Nextcloud base URL; download
credentials are not required for public APK shares and must not be embedded in
the app.

## Troubleshooting

- **Signing setup fails:** verify the four keystore secrets and ensure
  `KEYSTORE_BASE64` is one-line base64 for the original production keystore.
- **Share creation fails:** verify the Nextcloud account has upload/share
  permissions and public-link sharing is enabled.
- **Release registration fails:** verify the `NOTEN_SERVER_API_KEY` Actions
  secret matches the server's configured API key and that the server endpoint
  is reachable.
- **The app rejects an APK:** check that the uploaded APK has the expected
  package ID and version and was signed with the original app keystore.
