## Day 1 & Day 2

I've decided to try building a game using [Zama's fhEVM](https://www.zama.ai/fhevm), a custom EVM blockchain where data can be encrypted and operated upon homomorphically.  

Homomorphic encryption allows the blockchain to store secret information, and only reveal it to specified users under certain conditions.  It's a different from an oracle in that it's possible to manipulate the encrypted values directly on-chain, but there are caveats: it's expensive, the data types are limited, and contract logic needs to prevent information from leaking.

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

Basic UI is put together.  I've realized that the "player point balance" also needs to be initialized, which I attempted to accomplish by generating a random euint32, then subtracting it from itself.  This did not work.

What _did_ work was using the "decrypt" function on the subtractor, then subtracting, but this is less than desirable because the use of "decrypt" is discouraged except in very specific cases.

However, time is limited, so if I can, I'll revisit the code later to try and remove the decrypts.  For now, everything seems to be working - the player can join a game, set traps, mine a space to increase their score, and end the game, earning points if they win.  I'll create a nicer UI tomorrow.

# Day 3

The game will have a top-down camera, with the player controlling a 3D character on a flat plateau.

https://github.com/Cactoidal/ZAMAfhEVMGame/assets/115384394/5d5d69e4-84fa-4e2b-a18d-c774b0290e5c

When you move around, invisible tiles will become visible when you stand on top of them.  As mentioned above, the game will be split into two phases.  When pressing space bar on top of a tile, you will either place a trap (during the trap phase), or place a mining machine (during the mining phase).

There will also be a clickable button that progresses the phases ("finish setting traps" and "stop mining", respectively).  Mining machines will have some kind of visual indicator to show they are "working" while the transaction is being processed.  Once the game detects a change in the player's score, it will resolve the fate of that machine (if it hit a trap, it will explode, and the game session will end).

Rather than ending automatically, the player will be prompted to end the game; the reason being that, were the "end game" transaction automatic when a trap is hit, an on-chain observer would be able to guess with high certainty that the other player had hit a trap, since the transaction would come out very quickly after the previous transaction finished. 

https://github.com/Cactoidal/ZAMAfhEVMGame/assets/115384394/9acfc5c1-d582-4ada-a069-5ec3ef136d97




