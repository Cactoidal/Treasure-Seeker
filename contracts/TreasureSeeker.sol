// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "fhevm/lib/TFHE.sol";
import "fhevm/abstracts/EIP712WithModifier.sol";

contract TreasureSeeker is EIP712WithModifier {

    mapping (address => bool) public playerInitialized;
    mapping (address => euint32) public playerPoints;

    address[2] matchmaker;
    mapping (address => uint) public queueStartTime;
    mapping (address => bool) public waitingForMatch;
    uint gameId = 1;
    mapping (address => uint) gameSession;
    mapping (address => bool) public inGame;
    mapping (address => address) public currentOpponent;
    mapping (address => euint8) baseResources;
    mapping (address => euint8) currentResources;
    mapping (address => euint8[3]) traps;
    mapping (address => bool) public hasSetTraps;
    mapping (address => bool) public activeMiner;
    mapping (uint => mapping (address => mapping (uint8 => bool))) minedLocations;
    mapping (address => bool) public readyToEnd;
    mapping (address => uint) public lastAction;

    constructor() EIP712WithModifier("Authorization token", "1") {

    }

    



    function joinMatch() public {
        require(inGame[msg.sender] == false);
        require(waitingForMatch[msg.sender] == false);

        // Player's initial overall point total must be homomorphically encrypted
        if (playerInitialized[msg.sender] == false) {
            playerInitialized[msg.sender] = true;
            playerPoints[msg.sender] = TFHE.randEuint32();
            playerPoints[msg.sender] = TFHE.sub(playerPoints[msg.sender],  playerPoints[msg.sender]);
        }

        // Initialize "base resource" value.  It cannot be too low or too high, to prevent underflow/overflow
        // This value will be used as a comparator later, and is meant to obscure the player's in-game status
        baseResources[msg.sender] = TFHE.randEuint8();
        ebool lowResources = TFHE.lt(baseResources[msg.sender], 100);
        baseResources[msg.sender] = TFHE.cmux(lowResources, TFHE.add(baseResources[msg.sender], 99), baseResources[msg.sender]);
        ebool highResources = TFHE.gt(baseResources[msg.sender], 200);
        baseResources[msg.sender] = TFHE.cmux(highResources, TFHE.sub(baseResources[msg.sender], 99), baseResources[msg.sender]);

        // If matchmaking queue is empty, become player 1
        address currentPlayer1 = matchmaker[0];
        if (currentPlayer1 == address(0x0)) {
            matchmaker[0] = msg.sender;
            waitingForMatch[msg.sender] = true;
            queueStartTime[msg.sender] = block.number + 50;
        }
        // If someone has been sitting in the queue for 50 blocks, they are kicked out and replaced
        else if (queueStartTime[currentPlayer1] < block.number) {
            waitingForMatch[currentPlayer1] = false;
            matchmaker[0] = msg.sender;
            waitingForMatch[msg.sender] = true;
            queueStartTime[msg.sender] = block.number + 50;
        }
        // Otherwise, become player 2.  Both players now enter the game, and their "current resource"
        // value is set.  This value will be used as a comparator later, to determine
        // how many points the player obtained during the game.
        else {
            waitingForMatch[currentPlayer1] = false;
            matchmaker[1] = msg.sender;

            currentOpponent[msg.sender] = currentPlayer1;
            currentOpponent[currentPlayer1] = msg.sender;

            inGame[currentPlayer1] = true;
            inGame[msg.sender] = true;

            currentResources[currentPlayer1] = baseResources[currentPlayer1];
            currentResources[msg.sender] = baseResources[msg.sender];

            lastAction[currentPlayer1] = block.number;
            lastAction[msg.sender] = block.number;

            gameSession[currentPlayer1] = gameId;
            gameSession[msg.sender] = gameId;

            minedTileLength[gameId][currentPlayer1] = 1;
            minedTileLength[gameId][msg.sender] = 1;

            gameId++;

            matchmaker[0] = address(0x0);
            matchmaker[1] = address(0x0);
        }

    }

    function exitQueue() public {
        require(waitingForMatch[msg.sender] == true);
        matchmaker[0] = address(0x0);
        waitingForMatch[msg.sender] = false;
    }


    // Choose 3 spots on the board to trap
    // A modder could try to trap outside the boundaries of the board (0-24), or stack traps on the same space,
    // but these OoB traps would have no effect on the game, aside from reducing the number of traps in play
    function setTraps(bytes calldata _trap1, bytes calldata _trap2, bytes calldata _trap3) public {
        require(inGame[msg.sender] == true);
        require(hasSetTraps[msg.sender] == false);
        euint8 trap1 = TFHE.asEuint8(_trap1);
        euint8 trap2 = TFHE.asEuint8(_trap2);
        euint8 trap3 = TFHE.asEuint8(_trap3);
        traps[msg.sender] = [trap1,trap2,trap3];
        hasSetTraps[msg.sender] = true;
        activeMiner[msg.sender] = true;
        lastAction[msg.sender] = block.number;
    }



    mapping (uint => euint8) usedSpots;
    uint8 public usedSpotLength = 1;

    mapping (uint => mapping (address => mapping (uint8 => euint8))) minedTiles;
    mapping (uint => mapping(address => uint8)) minedTileLength;

    function makeThing() public {
        euint8 newThing = TFHE.randEuint8();
        uint i = 1;
        euint8 detectMinedBase = TFHE.randEuint8();
        detectMinedBase = TFHE.sub(detectMinedBase, detectMinedBase);
        euint8 detectMined = detectMinedBase;
        uint arrayLength = usedSpotLength;
        for (i; i < arrayLength; i++) {
            ebool alreadyMined = TFHE.eq(newThing, usedSpots[i]);
            detectMined = TFHE.cmux(alreadyMined, TFHE.add(detectMined, 1), detectMined);
        }
        ebool wasAlreadyMined = TFHE.gt(detectMined, detectMinedBase);
        //currentResources[msg.sender] = TFHE.cmux(wasAlreadyMined, TFHE.sub(resources, 33), TFHE.add(resources, 1));
        usedSpots[usedSpotLength] = newThing;
        usedSpotLength++;
    }


    // New tryMine() transaction to correct information leak (currently testing)

    // Choose a spot to mine.  If the mine has a trap, you will lose 33 points.  Otherwise, you gain 1 point.
    // Must mine within the boundaries of the board (0-24)
    // Can't mine in the same spot twice
    function tryMine2(euint8 location) public {
        address opponent = currentOpponent[msg.sender];
        euint8 resources = currentResources[msg.sender];

        require(activeMiner[msg.sender] == true);
        require(hasSetTraps[opponent] == true);

        // Check that the tile is not greater than 24
        ebool outOfBounds = TFHE.gt(location, 24);
        resources = TFHE.cmux(outOfBounds, TFHE.sub(resources, resources), resources);

        // Check that the tile has not been mined more than once
        uint session = gameSession[msg.sender];
        uint8 arrayLength = minedTileLength[session][msg.sender];

        uint8 k = 1;
        euint8 detectMinedBase = TFHE.randEuint8();
        detectMinedBase = TFHE.sub(detectMinedBase, detectMinedBase);
        euint8 detectMined = detectMinedBase;

        // Tile cannot match an existing mapping, or the player will lose
        for (k; k < arrayLength; k++) {
            ebool alreadyMined = TFHE.eq(location, minedTiles[session][msg.sender][k]);
            detectMined = TFHE.cmux(alreadyMined, TFHE.add(detectMined, 1), detectMined);
        }
        ebool wasAlreadyMined = TFHE.gt(detectMined, detectMinedBase);
        resources = TFHE.cmux(wasAlreadyMined, TFHE.sub(resources, resources), resources);

        // Map the tile
        minedTiles[session][msg.sender][arrayLength] = location;
        minedTileLength[session][msg.sender]++;

        // Now check whether the tile was trapped
        euint8 detectTrappedBase = TFHE.randEuint8();
        ebool lowRand = TFHE.lt(detectTrappedBase, 3);
        detectTrappedBase = TFHE.cmux(lowRand, TFHE.add(detectTrappedBase, 3), detectTrappedBase);
        euint8 detectTrapped = detectTrappedBase;

        // Scoping variables to prevent stack too deep error
        address _opponent = opponent;
        euint8 _location = location;
        euint8 _resources = resources;

        // Check whether the given location matches a trapped tile
        for (uint i; i < 3; i++) {
            ebool trapped = TFHE.eq(traps[_opponent][i], _location);
            detectTrapped = TFHE.cmux(trapped, TFHE.sub(detectTrapped, 1), detectTrapped);
        }

        ebool wasTrapped = TFHE.lt(detectTrapped, detectTrappedBase);
        currentResources[msg.sender] = TFHE.cmux(wasTrapped, TFHE.sub(_resources, _resources), TFHE.add(_resources, 1));
        lastAction[msg.sender] = block.number;
    }



    // Choose a spot to mine.  If the mine has a trap, you will lose 33 points.  Otherwise, you gain 1 point.
    // Must mine within the boundaries of the board (0-24)
    // Can't mine in the same spot twice
    function tryMine(uint8 location) public {
        require (location >= 0 && location < 25);
        require (minedLocations[gameSession[msg.sender]][msg.sender][location] == false);
        minedLocations[gameSession[msg.sender]][msg.sender][location] = true;

        address opponent = currentOpponent[msg.sender];
        euint8 resources = currentResources[msg.sender];

        require(activeMiner[msg.sender] == true);
        require(hasSetTraps[opponent] == true);

        euint8 detectTrappedBase = TFHE.randEuint8();
        ebool lowRand = TFHE.lt(detectTrappedBase, 3);
        detectTrappedBase = TFHE.cmux(lowRand, TFHE.add(detectTrappedBase, 3), detectTrappedBase);
        euint8 detectTrapped = detectTrappedBase;

        // Check whether the given location matches a trapped tile
        for (uint i; i < 3; i++) {
            ebool trapped = TFHE.eq(traps[opponent][i], location);
            detectTrapped = TFHE.cmux(trapped, TFHE.sub(detectTrapped, 1), detectTrapped);
        }

        ebool wasTrapped = TFHE.lt(detectTrapped, detectTrappedBase);
        currentResources[msg.sender] = TFHE.cmux(wasTrapped, TFHE.sub(resources, 33), TFHE.add(resources, 1));
        lastAction[msg.sender] = block.number;
    }

    // If you are happy with your score (or ready to resign), you may signal that you are ready to end the game.
    // If both players have signalled, the game will end.
    // Player scores are obtained by comparing and subtracting the "base resource" from the "current resource".
    // The player scores are then compared to determine the winner.
    // The winner's overall point total is increased by their score.
    // Both players are reinitialized.
    function stopMining() public {
        require(inGame[msg.sender] == true);
        require(activeMiner[msg.sender] == true);
        address opponent = currentOpponent[msg.sender];

        if (readyToEnd[opponent] == true) {

            euint8 playerBaseScore = baseResources[msg.sender];
            euint8 playerCurrentScore = currentResources[msg.sender];
            euint8 opponentBaseScore = baseResources[opponent];
            euint8 opponentCurrentScore = currentResources[opponent];

            ebool playerScoreAboveZero = TFHE.gt(playerCurrentScore, playerBaseScore);
            euint8 playerScore = TFHE.cmux(playerScoreAboveZero, TFHE.sub(playerCurrentScore, playerBaseScore), TFHE.sub(playerBaseScore, playerBaseScore));

            ebool opponentScoreAboveZero = TFHE.gt(opponentCurrentScore, opponentBaseScore);
            euint8 opponentScore = TFHE.cmux(opponentScoreAboveZero, TFHE.sub(opponentCurrentScore, opponentBaseScore), TFHE.sub(opponentBaseScore, opponentBaseScore));

            ebool playerWon = TFHE.gt(playerScore, opponentScore);
            playerPoints[msg.sender] = TFHE.cmux(playerWon, TFHE.add(playerPoints[msg.sender], playerScore), playerPoints[msg.sender]);
            
            ebool opponentWon = TFHE.gt(opponentScore, playerScore);
            playerPoints[opponent] = TFHE.cmux(opponentWon, TFHE.add(playerPoints[opponent], opponentScore), playerPoints[opponent]);

            inGame[msg.sender] = false;
            inGame[opponent] = false;
            activeMiner[msg.sender] = false;
            readyToEnd[opponent] = false;
            hasSetTraps[msg.sender] = false;
            hasSetTraps[opponent] = false;
        }
        else {
            activeMiner[msg.sender] = false;
            readyToEnd[msg.sender] = true;
        }
    }

    // If a player has not acted for 20 blocks, you may end the game.
    // You gain points if your score is higher than 0.
    function forceEndGame() public {
        address opponent = currentOpponent[msg.sender];
        require (inGame[msg.sender] == true);
        require (readyToEnd[opponent] == false);
        require (lastAction[msg.sender] > lastAction[opponent]);
        require (block.number >= lastAction[msg.sender] + 20);

        ebool playerScoreAboveZero = TFHE.gt(currentResources[msg.sender], baseResources[msg.sender]);
        euint8 playerScore = TFHE.cmux(playerScoreAboveZero, TFHE.sub(currentResources[msg.sender], baseResources[msg.sender]), TFHE.sub(baseResources[msg.sender], baseResources[msg.sender]));
        playerPoints[msg.sender] = TFHE.add(playerPoints[msg.sender], playerScore);

        inGame[msg.sender] = false;
        inGame[opponent] = false;
        readyToEnd[msg.sender] = false;
        readyToEnd[opponent] = false;
        hasSetTraps[msg.sender] = false;
        hasSetTraps[opponent] = false;
        activeMiner[msg.sender] = false;
        activeMiner[opponent] = false;


    }
  
    // To observe changes during gameplay, the game needs to know the "current score" over time.
    // This raw value will not be visible to the player, and instead its 
    // increases/decreases will be tracked by Godot
    function trackScore(
        bytes32 publicKey,
        bytes calldata signature
        ) public view onlySignedPublicKey(publicKey, signature) returns (bytes memory) {
            return TFHE.reencrypt(currentResources[msg.sender], publicKey, 0);
        }
    


    // The overall point total across all matches the player has won.  Checked after the match
    // to see if the player won or lost the match.
    function getPointsBalance(
        bytes32 publicKey,
        bytes calldata signature
        ) public view onlySignedPublicKey(publicKey, signature) returns (bytes memory) {
            return TFHE.reencrypt(playerPoints[msg.sender], publicKey, 0);
        }
        
  }







