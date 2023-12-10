## Day 1 & Day 2

I've decided to try building a game using [Zama's fhEVM](https://www.zama.ai/fhevm), a custom EVM blockchain where data can be encrypted and operated upon homomorphically.  

Homomorphic encryption allows the blockchain to store secret information, and only reveal it to specified users under certain conditions.  It's a bit more flexible than an oracle in that it's possible to manipulate the encrypted values directly on-chain, but there are caveats: it's expensive, the data types are limited, and contract logic needs to prevent information from leaking.

By the latter point, I mean that conditional checking (such as "is this homomorphic number greater than another number") must be written to prevent an attacker from figuring out the homomorphic number by repeatedly guessing.

This is possible by using the "cmux" function.  Comparison operators (less than, greater than, equal to, etc.) can be used to compare homomorphic values, producing a homomorphic boolean.

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

I've decided to take a different tack when it comes to initializing values.  Instead of using the built-in PRNG function and manipulating the random value into a suitable range, I will instead ask the player to provide a specific value (such as 0) as a homomorphically encrypted value.

While everyone will know what the initial values are, what matters for this game is obscuring the _changes_ to that value over time.  For instance, both players will start with the same initial "base score" each game.  Whenever they mine a square, that value will change, but it will be impossible for an on-chain observer to know if it went up (wasn't trapped) or down (was trapped).

To set this initial value, my solution is slightly hacky.  The player provides the euint, then the contract checks if that euint is equal to the expected value, setting an ebool to the result.  Cmux checks the ebool, and if it is false, it will revert the transaction with a deliberate error by attempting to set a variable to an uninitialized euint.

I have another problem at the end of the game, however.  From a game design perspective, I think it would be better if the game is instantly lost as soon as you hit a trap.

I had originally planned to do this by checking the "current score" against the "base score", and if the current score is smaller, the contract knows you hit a trap, and would set your "actual score" to 0 by subtracting the base score by itself.

This doesn't actually seem to be possible, unless I use "decrypt", which I'm trying to avoid.  So, I have a few options:
1) use decrypt, accepting that it's suboptimal
2) change the game's design to directly compare the player's "current scores" at the end, which would mean that it's still possible to win after hitting a trap, which significantly changes the risk calculus and extends the length of the game
3) try to find some clever use of cmux and filtering to achieve the same design I currently have
