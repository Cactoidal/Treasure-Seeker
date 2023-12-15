fhEVM CONTRACT

[TreasureSeeker.sol](https://github.com/Cactoidal/Treasure-Seeker/blob/main/contracts/TreasureSeeker.sol) - maintains secrecy of game sessions by obscuring trapped tiles and player scores.  Uses homomorphic operations to detect when traps are hit and determine the winner of a match

RUST

[lib.rs](https://github.com/Cactoidal/Treasure-Seeker/blob/main/godot/rust/lib.rs) - formats calldata and EIP712 signatures, generates cryptobox keypairs and decrypts data

GODOT

[TitleScreen.gd](https://github.com/Cactoidal/Treasure-Seeker/blob/main/godot/TitleScreen.gd) - main hub of the game, contains all eth_call and eth_sendRawTransaction functions, handles queueing and initializing game sessions

[Player.gd](https://github.com/Cactoidal/Treasure-Seeker/blob/main/godot/Player.gd) - controller of a game session, takes player inputs and renders effects of transactions
