# Android releases and in-app updates

## Release flow

Both Android release workflows build and sign an APK, verify its version and
signature, retain a short-lived GitHub Actions artifact, and upload the APK to
the Nextcloud `releases` folder. Octopus creates and deploys the release and is
the only component that announces it to the noten-server. GitHub Actions must
not call the server release API directly.

The Octopus deployment must make the APK available through a public HTTPS URL
and publish the release using the server's configured API key. On connection,
clients receive the currently published release; connected clients can also
receive `release_announce` for their app.

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
- Configure these GitHub Actions secrets in **both** app repositories:
  `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`,
  `NC_USER`, `NC_PASS`, `OCTOPUS_API_KEY`, and `OCTOPUS_SPACE`.
- Configure the noten-server API key and the public APK download URL in the
  Octopus deployment process. Keep those values out of GitHub Actions and app
  binaries; Octopus owns the server announcement.
- `KEYSTORE_BASE64` must contain the base64-encoded JKS used to sign the
  already-installed version of that app. Keep the keystore and passwords
  backed up securely; changing the signing key prevents Android from installing
  an update over existing installations.

The workflow validates all required signing secrets, decodes and verifies the
keystore alias, and fails before building if the keystore or its properties
are missing. The keystore and `key.properties` are generated only in the CI
workspace and are not included in the APK. The bundled
`assets/.env.example` contains only the public Nextcloud base URL; download
credentials are not embedded in the app.

## Troubleshooting

- **Signing setup fails:** verify the four keystore secrets and ensure
  `KEYSTORE_BASE64` is one-line base64 for the original production keystore.
- **APK upload fails:** verify the Nextcloud account can upload to the
  configured `releases` folder.
- **Octopus deployment or announcement fails:** verify the project, Production
  environment, server API key, and public HTTPS APK URL in Octopus.
- **The app rejects an APK:** check that the uploaded APK has the expected
  package ID and version and was signed with the original app keystore.
