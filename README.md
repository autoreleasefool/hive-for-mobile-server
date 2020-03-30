# Hive for iOS - Server

The backend for the [Hive for iOS](https://github.com/josephroquedev/hive-for-ios) app.

## API

For more information on the API, see [API.md](./API.md)

## Getttng Started

1. Open `hive-for-ios-server.xcodeproj` in Xcode
2. Select the `Run` scheme and choose the destination `My Mac`
3. Run the server
4. The app will be available at `localhost:8080`

### Optional

To set up the app for development, run the `script/dev` script to begin ngrok and set up the [Hive for iOS](https://github.com/josephroquedev/hive-for-ios) client to connect to your instance

## Requirements

* Swift 5.1+
* [Vapor](https://github.com/vapor/vapor)
* [SwiftLint](https://github.com/realm/SwiftLint)

## Contributing

1. Clone this repo
2. Make your changes and run `swiftlint` to ensure there are no lint errors
3. TODO: Testing
4. Open a PR with your changes (don't include ngrok URLs) 🎉
