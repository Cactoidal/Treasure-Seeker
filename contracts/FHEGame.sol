// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "fhevm/lib/TFHE.sol";
import "fhevm/abstracts/EIP712WithModifier.sol";

contract FHEGame is EIP712WithModifier {

    mapping (address => euint8) public secretNumber;
    bool public success;
    uint epochStart;
    //uint constant epochDivisor = 5000;
    uint constant epochDivisor = 50;
    mapping (uint => mapping (uint8 => euint16)) public epochResource;
    mapping (uint => mapping (uint8 => bool)) public epochMineStarted;
    mapping (uint => mapping (uint8 => ebool)) public epochMinedOut;
    mapping (address => euint32) playerPoints;


    address[2] matchmaker;
    mapping (address => uint) queueStartTime;
    mapping (address => bool) waitingForMatch;
    mapping (address => bool) public inGame;
    mapping (address => address) public currentOpponent;
    mapping (address => euint8) baseResources;
    mapping (address => euint8) currentResources;
    mapping (address => euint8[3]) traps;
    mapping (address => bool) hasSetTraps;
    mapping (address => bool) activeMiner;
    mapping (address => bool) readyToEnd;
    mapping (address => uint) lastAction;
   

    // For Testing
    address testOpponent;

    constructor() EIP712WithModifier("Authorization token", "1") {
        epochStart = block.number;
        testOpponent = address(this);
    }

    function joinMatch() public {
        require(inGame[msg.sender] == false);
        require(waitingForMatch[msg.sender] == false);

        //  For Testing   //
        matchmaker[0] = testOpponent;
        queueStartTime[testOpponent] = block.number + 10000; 
        baseResources[testOpponent] = TFHE.randEuint8();
        ebool lowOpponentResources = TFHE.lt(baseResources[testOpponent], 100);
        baseResources[testOpponent] = TFHE.cmux(lowOpponentResources, TFHE.add(baseResources[msg.sender], 99), baseResources[msg.sender]);
        ebool highOpponentResources = TFHE.gt(baseResources[testOpponent], 200);
        baseResources[testOpponent] = TFHE.cmux(highOpponentResources, TFHE.sub(baseResources[msg.sender], 99), baseResources[msg.sender]);
        ///////////

        // Initialize "base resource" value.  It cannot be too low or too high
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

            matchmaker[0] = address(0x0);
            matchmaker[1] = address(0x0);
        }

    }

    // Choose 3 spots on the board to trap
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


    // Choose a spot to mine.  If the mine has a trap, you will lose 33 points.  Otherwise, you gain 1 point.
    function tryMine(uint8 location) public {
        address opponent = currentOpponent[msg.sender];
        euint8 resources = currentResources[msg.sender];
        require(activeMiner[msg.sender] == true);
        require(hasSetTraps[opponent] == true);
        euint8 detectTrappedBase = TFHE.randEuint8();
        ebool lowRand = TFHE.eq(detectTrappedBase, 0);
        detectTrappedBase = TFHE.cmux(lowRand, TFHE.add(detectTrappedBase, 3), detectTrappedBase);
        euint8 detectTrapped = detectTrappedBase;
        for (uint i; i < 3; i++) {
            ebool trapped = TFHE.eq(traps[opponent][i], location);
            detectTrapped = TFHE.cmux(trapped, TFHE.sub(detectTrapped, 1), detectTrapped);
        }
        ebool wasTrapped = TFHE.lt(detectTrapped, detectTrappedBase);
        currentResources[msg.sender] = TFHE.cmux(wasTrapped, TFHE.sub(resources, 33), TFHE.add(resources, 1));
        lastAction[msg.sender] = block.number;
    }

    // If you are happy with your score, you may signal that you are ready to end the game.
    function stopMining() public {
        require(inGame[msg.sender] == true);
        require(activeMiner[msg.sender] == true);
        activeMiner[msg.sender] = false;
        readyToEnd[msg.sender] = true;
    }

    // Player scores are obtained by comparing and subtracting the "base resource" from the "current resource".
    // The player scores are then compared to determine the winner.
    // Both players are reinitialized.
    function endGame() public {
        address opponent = currentOpponent[msg.sender];
        require(readyToEnd[msg.sender] == true);
        require(readyToEnd[opponent] == true);
        inGame[msg.sender] = false;
        inGame[opponent] = false;
        readyToEnd[msg.sender] = false;
        readyToEnd[opponent] = false;
        hasSetTraps[msg.sender] = false;
        hasSetTraps[opponent] = false;

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

    }

    // If a player has not acted for 20 blocks, you may end the game.
    // You gain points if you have more than 0.
    function forceEndGame() public {
        address opponent = currentOpponent[msg.sender];
        require (inGame[msg.sender] == true);
        require (readyToEnd[opponent] == false);
        require (lastAction[msg.sender] > lastAction[opponent]);
        require (block.number >= lastAction[msg.sender] + 20);

        inGame[msg.sender] = false;
        inGame[opponent] = false;
        readyToEnd[msg.sender] = false;
        readyToEnd[opponent] = false;
        hasSetTraps[msg.sender] = false;
        hasSetTraps[opponent] = false;
        activeMiner[msg.sender] = false;
        activeMiner[opponent] = false;

        ebool playerScoreAboveZero = TFHE.gt(currentResources[msg.sender], baseResources[msg.sender]);
        euint8 playerScore = TFHE.cmux(playerScoreAboveZero, TFHE.sub(currentResources[msg.sender], baseResources[msg.sender]), TFHE.sub(baseResources[msg.sender], baseResources[msg.sender]));
        playerPoints[msg.sender] = TFHE.add(playerPoints[msg.sender], playerScore);


    }


    // Retrieve your current score using EIP712 key exchange
    function currentScore(
        bytes32 publicKey,
        bytes calldata signature
        ) public view onlySignedPublicKey(publicKey, signature) returns (bytes memory) {
            euint8 playerBaseScore = baseResources[msg.sender];
            euint8 playerCurrentScore = currentResources[msg.sender];

            ebool playerScoreAboveZero = TFHE.gt(playerCurrentScore, playerBaseScore);
            euint8 playerScore = TFHE.cmux(playerScoreAboveZero, TFHE.sub(playerCurrentScore, playerBaseScore), TFHE.sub(playerBaseScore, playerBaseScore));
            return TFHE.reencrypt(playerScore, publicKey, 0);
        }



    // Debug function
    function setNumber(bytes calldata _number) public {
        euint8 number = TFHE.asEuint8(_number);
        secretNumber[msg.sender] = number;
        success = true;
    }
    


  }







