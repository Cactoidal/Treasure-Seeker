## Day 1 & Day 2

I've decided to try building a game using [Zama's fhEVM](https://www.zama.ai/fhevm), a custom EVM blockchain where data can be encrypted and operated upon homomorphically.  

Homomorphic encryption allows the blockchain to store secret information, and only reveal it to specified users under certain conditions.  The biggest benefit of the fhEVM is its ability to manipulate encrypted values directly on-chain, without revealing them, but there are caveats: it's expensive, the data types are limited, and contract logic needs to prevent information from leaking.

By the latter point, I mean that conditional checking (such as "is this homomorphic number greater than another number") must be written to prevent an attacker from figuring out the homomorphic number by repeatedly guessing.

The "cmux" function can help avoid this problem.  Comparison operators (less than, greater than, equal to, etc.) can be used to compare homomorphic values, producing a homomorphic boolean.

The homomorphic boolean can then be used with cmux, which essentially takes that boolean and returns a homomorphic integer (case true) or a different homomorphic integer (case false).

Anyway, I have about a week to create a game.  Day 1 was spent testing Zama's [tfhe-rs crate](https://github.com/zama-ai/tfhe-rs). I've gotten it mostly working with ethers-rs.

This game will be pretty simple.  It's a 1v1 game split into two phases: trapping and mining.  During the trap phase, both players choose 3 spaces on the game board to trap.  Then mining begins.

Players may only mine a space one time.  If the space has no trap, they gain 1 point.  But if there is a trap, they will lose 33 points (which effectively means they have lost).

To win, you simply need to get more points than your opponent.  Your score is homomorphically encrypted, so you have no idea what your opponent's score is, just like you have no idea where the traps are.

After scoring a point, it's up to you whether you want to risk it for more, or stop mining and let it ride.  Only at the end will you find out whether it was enough to win.

The game starts by generating a random euint8 (homomorphically encrypted uint8) for each player, as their "base score".  To prevent potential underflows or overflows, the contract checks that the random value is within a certain range above 0 and below 255.

This "base score" initializes the player's "current score" value, which will make it impossible for an on-chain observer to know what the player's current score actually is.  It will also serve as a comparator later, to determine the player's actual final score.

Whenever the player mines a space, their "current score" will be modified homomorphically (either subtracting 33, or adding 1).

When both players have signaled their intent to end the game, their scores will be calculated by first checking whether their "current score" is less than their "base score" - if so, it means they hit a trap, and their "actual score" is set to 0.  Otherwise, their "base score" is subtracted from the "current score" to get the "actual score".

The two "actual scores" are then compared.  Whoever's score is greater is the winner, and their homomorphic "points balance" will be incremented by whatever score they had.  The game is then over.  Draws award no points.

<img width="1009" alt="1FHEGame" src="https://github.com/Cactoidal/ZAMAfhEVMGame/assets/115384394/f123b91a-66bb-48cf-abfd-70b12105455e">

Basic UI is put together.  I've realized that the "player point balance" also needs to be initialized, which I accomplished by generating a random euint32, then subtracting it from itself.

Everything seems to be working - the player can join a game, set traps, mine a space to increase their score, and end the game, earning points if they win.  I'll create a nicer UI tomorrow.

## Day 3

The game will have a top-down camera, with the player controlling a 3D character on a flat plateau.

https://github.com/Cactoidal/ZAMAfhEVMGame/assets/115384394/5d5d69e4-84fa-4e2b-a18d-c774b0290e5c

When you move around, invisible tiles will become visible when you stand on top of them.  As mentioned above, the game will be split into two phases.  When pressing space bar on top of a tile, you will either place a trap (during the trap phase), or place a mining machine (during the mining phase).

There will also be a clickable button that progresses the phases ("finish setting traps" and "stop mining", respectively).  Mining machines will have some kind of visual indicator to show they are "working" while the transaction is being processed.  Once the game detects a change in the player's score, it will resolve the fate of that machine (if it hit a trap, it will explode, and the game session will end).

Rather than ending automatically, the player will be prompted to end the game; the reason being that, were the "end game" transaction automatic when a trap is hit, an on-chain observer would be able to guess with high certainty that the other player had hit a trap, since the transaction would come out very quickly after the previous transaction finished. 

https://github.com/Cactoidal/ZAMAfhEVMGame/assets/115384394/9acfc5c1-d582-4ada-a069-5ec3ef136d97

No sending transactions yet, but we're getting there:

https://github.com/Cactoidal/ZAMAfhEVMGame/assets/115384394/dac8946c-ec47-434e-bba1-5bcf29e75e16

We also now have a name for our game: "Treasure Seeker", and a fancy new title screen:

https://github.com/Cactoidal/Treasure-Seeker/assets/115384394/7a4e4cf5-eac1-4b9d-a0a0-01147c6c85c5

The infinite terrain is just 3 meshes that leapfrog each other as the camera moves forward.  The terrain shape itself is [generated by a shader](https://www.reddit.com/r/godot/comments/z7r13b/cheap_3d_terrain_generator_with_noise_texture_for/), courtesy of the user AllenGnr.  

[AllSky's skyboxes](https://github.com/rpgwhitelock/AllSkyFree_Godot/blob/master/addons/AllSkyFree/Skyboxes/AllSkyFree_Sky_OvercastLow_Equirect.png) are once again very handy.  I've got it slowly rotating to make the clouds seem like they're moving.  The moon, a TextureRectangle, completes the illusion.

## Day 4

Still a bit of work to do.  Transactions are hooked up (but turned off for the video I'm about to post).  View functions constitute the biggest remaining hurdle.  Godot needs to know the player's on-chain score to determine whether they hit a trap.  That score is homomorphically encrypted, which means the game needs to request the decrypted value.

Right now, I just have a debug function that decrypts the value for anyone.  Obviously, that's not secure.  The correct way to retrieve these values involves creating a public/private keypair locally, and sending the public key to the RPC, which will decrypt the homomorphic value and reencrypt it with the public key before sending it back.

https://github.com/Cactoidal/Treasure-Seeker/assets/115384394/7f8e67c0-f8d7-4e90-98b9-cfb92aea1c08

The whole shebang.  I'm liking the minimal style, so while there need to be some indicators during the mining phase, I think this is pretty much set graphics-wise.  The background is auntygames' [Pixel Water shader](https://godotshaders.com/shader/pixel-ghibli-water/).  It's been applied as a Viewport texture to a plane mesh underneath the cube mesh the player walks on.  Pretty neat.

## Day 5

After some assistance from ChatGPT and quite a bit of trial and error, I've now implemented the EIP712 signing standard expected by the contract.  This allows the player to generate a crypto_box public/private keypair using libsodium-sys, sign the public key, and pass it to the contract.  Next up: making the game ready for competitive play, now that all the pieces have been assembled.

## Day 6

Happy to report that the game is now fully hooked up to the smart contract and can be played start-to-finish.  It uses the chain public key to homomorphically encrypt the trap values, and it uses the cryptobox keypair and EIP712 standard to request and reencrypt the game session score, so it can know whether you hit a trap while mining.

Just a bit more needs to be done.  There are some graphical problems to address, and the player also needs to know whether they won.  This will be accomplished by checking the player's "point balance" before and after the game session; if it went up, then they won the game.

Once these pieces are complete, I can remove the test opponent and try some live 1v1s.  

As a side note, sometime in the next few months I plan to make the switch from ethers-rs to Alloy, and from Godot 3.5 to Godot 4.2.  During that time I'd like to think carefully about my coding patterns.

My games typically center around two scripts: the "main script" that instantiates the game session, and which contains all of the transaction logic, and the "game script" which takes player inputs and displays visual effects.

I'm wondering if there is a way to simplify or streamline the relationship between these scripts, since right now the end product can end up somewhat convoluted, with the scripts referring to one another back and forth.

I also have quite a bit of repetitive code, both in gdscript and in Rust, that I'm hoping I can cut down, to make the system easier to audit and replicate.

## Day 7

After some live 1v1 playtesting, I've found a few bugs that could be RPC related.  On rare occasions, something happens to the reencrypted value during transit, which causes Godot to incorrectly report the incoming score as a 0.  Since the game is just checking whether the incoming score is lower than the current recorded score, this tricks the game into reporting that the tile was trapped.

To get around this, for now I've just programmed the game to ignore incoming scores of 0.  My hypothesis is that this may have to do with how I've hardcoded the RPC request id numbers, but I'm not quite sure, and the error is difficult to replicate.

More commonly, transactions get dropped entirely, which can make the game hang up during queueing.  Running the game with a local RPC would probably solve these problems.

Regardless, there is now a [public release available for MacOSX and Linux/X11](https://github.com/Cactoidal/Treasure-Seeker/releases/tag/v0.1.0-alpha)!  If you'd like to try it, you should definitely play with a friend, otherwise you will simply sit in the queue.

I've also created a [short demo video](https://www.youtube.com/watch?v=wdNZbRqhCMY) showing the gameplay, and explaining the contract logic.

And that brings this first experiment with the fhEVM to a close.  As always, thanks for reading.

___

After submitting the work, I've realized that there is a big problem with the design: when cleartext locations are submitted during mining, the opponent can of course know whether the player has hit a trap.

While the locations could be passed as euint8s intead, this introduces another issue.

The player can't be allowed to mine the same location twice, otherwise they could farm points infinitely.  There doesn't seem to be an easy homomorphic way to check which tiles have been mined.  The euint8 can't be used in the "minedLocations" mapping, because the ciphertext for the same euint8 will be different every time it is made.

I still have a couple days to think this over until the actual deadline, but this may be an intractable problem.  The traps, at least, do remain secret until they are hit, which is something that would be very difficult to do without the fhEVM.  

But the score was also kept homomorphic, because my intent was that neither player should know the fate of the other until the very end of the game.  As it stands, because I've used cleartext locations to prevent the same tile being mined twice, knowledge of the other player's score leaks with every transaction.




