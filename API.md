# API

## REST

### Users

**POST** api/users/signup - Sign up

<summary>Example input</summary>
<details>
```
{
	"email": "example@mail.com",
	"password": "password",
	"verifyPassword": "password",
	"displayName": "chosenUsername"
}
```
</details>

<summary>Example response</summary>
<details>
```
{
	"id": "SomeUserID",
	"email": "example@mail.com",
	"displayName": "chosenUsername",
	"avatarUrl": null,
	"token": "SomeAccessToken"
}
```
</details>

**POST** api/users/login - Login

<summary>Example input</summary>
<details>
```
{
	"email": "email@mail.com",
	"password": "password"
}
```
</details>

<summary>Example response</summary>
<details>
```
{
	"id": "SomeTokenID",
	"userId": "SomeUserID",
	"token": "SomeAccessToken"
}
```
</details>

**DELETE** api/users/logout - Logout

<summary>Example response</summary>
<details>
`OK`
</details>

**GET** api/users/validate - Token validation

<summary>Example response</summary>
<details>
{
	"userId": "SomeUserID",
	"token": "SomeAccessToken"
}
</details>

**GET** api/users/ID/details - User details

<summary>Example response</summary>
<details>
```
{
	"id": "SomeUserID",
	"displayName": "chosenUsername",
	"elo": 1000.0,
	"avatarUrl": "https://example.com/image.png",
	"activeMatches": [
	],
	"pastMatches": [
	]
}
```
</details>

**GET** api/users/ID/summary - User summary

<summary>Example response</summary>
<details>
```
{
	"id": "SomeUserID",
	"displayName": "chosenUsername",
	"elo": 1000.0,
	"avatarUrl": "https://example.com/image.png",
}
```
</details>

**GET** api/users/all - List of all users

<summary>Example response</summary>
<details>
```
[
	{
		"id": "SomeUserID",
		"displayName": "chosenUsername",
		"elo": 1000.0,
		"avatarUrl": "https://example.com/image.png",
	},
	{
		"id": "SomeUserID2",
		"displayName": "chosenUsername2",
		"elo": 1000.0,
		"avatarUrl": "https://example.com/image.png",
	}
]
```
</details>

### Matches

**GET** api/matches/open - List of open matches

<summary>Example response</summary>
<details>
```
[
]
```
</details>

**GET** api/matches/active - List of active matches

<summary>Example response</summary>
<details>
```
[
]
```
</details>

**GET** api/matches/ID - Match details

<summary>Example response</summary>
<details>
```
{
	"id": "SomeMatchID",
	"hostElo": 1000.0,
	"opponentElo": 1000.0,
	"options": "HostIsWhite:false;AsyncPlay:false",
	"gameOptions": "LadyBug:true;Mosquito:true;NoFirstMoveQueen:false",
	"createdAt": "2020-03-30T00:00:00.000Z"
	"duration": null,
	"status": "notStarted",
	"isComplete": false,
	"host": {
		"id": "SomeUserID",
		"displayName": "chosenUsername",
		"elo": 1000.0,
		"avatarUrl": "https://example.com/image.png",
	},
	"opponent": {
		"id": "SomeUserID2",
		"displayName": "chosenUsername2",
		"elo": 1000.0,
		"avatarUrl": "https://example.com/image.png",
	},
	"winner": null,
	"moves": [
		{
			"id": "SomeMovementID",
			"notation": "wQ",
			"ordinal": 1
		},
		{
			"id": "SomeMovementID2",
			"notation": "bQ -wQ",
			"ordinal": 2
		}
	],
}
```
</details>

**POST** api/matches/ID/join - Join match

<summary>Example response</summary>
<details>
```
{
	"id": "SomeMatchID",
	"hostElo": 1000.0,
	"opponentElo": 1000.0,
	"options": "HostIsWhite:false;AsyncPlay:false",
	"gameOptions": "LadyBug:true;Mosquito:true;NoFirstMoveQueen:false",
	"createdAt": "2020-03-30T00:00:00.000Z"
	"duration": null,
	"status": "notStarted",
	"isComplete": false,
	"host": {
		"id": "SomeUserID",
		"displayName": "chosenUsername",
		"elo": 1000.0,
		"avatarUrl": "https://example.com/image.png",
	},
	"opponent": {
		"id": "SomeUserID2",
		"displayName": "chosenUsername2",
		"elo": 1000.0,
		"avatarUrl": "https://example.com/image.png",
	},
	"winner": null,
	"moves": [],
}
```
</details>

**POST** api/matches/new - Create match

<summary>Example response</summary>
<details>
```
{
	"id": "SomeMatchID",
	"hostElo": 1000.0,
	"opponentElo": null,
	"options": "HostIsWhite:false;AsyncPlay:false",
	"gameOptions": "LadyBug:true;Mosquito:true;NoFirstMoveQueen:false",
	"createdAt": "2020-03-30T00:00:00.000Z"
	"duration": null,
	"status": "notStarted",
	"isComplete": false,
	"host": {
		"id": "SomeUserID",
		"displayName": "chosenUsername",
		"elo": 1000.0,
		"avatarUrl": "https://example.com/image.png",
	},
	"opponent": null,
	"winner": null,
	"moves": [],
}
```
</details>

## WebSocket

Endpoint: `<SERVER_URL>/matchID/play`

### Commands

Once connected to a WebSocket, you can send commands of the following formats:

**SET _option_ _value_**: Set the value of an option _option_ to _value_. See the [Match options](/Sources/App/Models/Match.swift) and the [Hive Engine](https://github.com/josephroquedev/hive-engine) for a list of options that are available.

**MSG _message_**: Send a message _message_ to your opponent.

**GLHF**: Indicate that you are ready for the game to begin

**MOV _movement_**: Make a move. See the [Hive Engine](https://github.com/josephroquedev/hive-engine) for movement notation

**FF**: Forfeit the current game.

### Responses

In response to your commands, or in response to the commands of other users in the same match, you can receive responses of the following formats:

**STATE _gameStateString_**: The current state of the game. See the [Hive Engine](https://github.com/josephroquedev/hive-engine) for the format of this String.

**WINNER _userId_**: The game has ended and the winner has been determined. The winner is either `userId` or `null` if the game ended in a tie.

**SET _option_ _value_**: Set the value of an option _option_ to _value_. See the [Match options](/Sources/App/Models/Match.swift) and the [Hive Engine](https://github.com/josephroquedev/hive-engine) for a list of options that are available.

**READY _userID_ _isReady_**: Indicate that a player is ready or not.

**MSG _message_**: Received a message from your opponent.

**FF _userID_**: A user has forfeit the game.

**ERR _code_ _description_** An error has occurred. See  [WSServerResponseError](./Sources/App/WebSocket/Message/Response/WSServerResponseError.swift) for possible errors.
