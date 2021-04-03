![Header](media/header.png)

# Hive for Mobile - Server

The backend for the [Hive for iOS](https://github.com/autoreleasefool/hive-for-ios) app.

## API

For more information on the API, see [API.md](./API.md)

## Getttng Started

1. Run `vapor xcode` to generate the Xcode project
1. Open `Hive-for-Mobile-Server.xcodeproj` in Xcode
1. Select the `Run` scheme and choose the destination `My Mac`
1. Run the server
1. The app will be available at `localhost:8080`

#### Requirements

- Swift 5.3+
- [Vapor](https://github.com/vapor/vapor)
- [SwiftLint](https://github.com/realm/SwiftLint)

### Development

To set up the app for development, run the `script/dev-setup` script to begin ngrok and set up the [Hive for iOS](https://github.com/autoreleasefool/hive-for-ios) client to connect to your instance

#### Requirements

- macOS
- [nginx](https://nginx.org/en/docs/)
- [ngrok](https://ngrok.com)

### Deploying

To set up the app to be deployed, run the `script/prod-setup` script to copy the configuration files to the appropriate directories.

#### Requirements

- Ubuntu
- [nginx](https://nginx.org/en/docs/)
- [supervisor](http://supervisord.org)

## Contributing

1. Clone this repo
1. Make your changes and run `swiftlint` to ensure there are no lint errors
1. TODO: Testing
1. Open a PR with your changes (don't include ngrok URLs) 🎉

## Notice

Hive for Mobile Server is not affiliated with Gen42 Games in any way.
