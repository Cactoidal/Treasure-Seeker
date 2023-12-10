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
    mapping (address => euint32) playerBalance;


    address[2] matchmaker;
    mapping (address => uint) queueStartTime;
    mapping (address => bool) waitingForMatch;
    mapping (address => bool) public inGame;
    mapping (address => address) public currentOpponent;
    mapping (address => euint8) baseResources;
    mapping (address => euint8) currentResources;
    mapping (address => euint8[3]) traps;
    mapping (address => bool) hasSetTraps;
   

    // For Testing
    address testOpponent = address(this);

    constructor() EIP712WithModifier("Authorization token", "1") {
        epochStart = block.number;
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
        ///////////

        baseResources[msg.sender] = TFHE.randEuint8();
        ebool lowResources = TFHE.lt(baseResources[msg.sender], 100);
        baseResources[msg.sender] = TFHE.cmux(lowResources, TFHE.add(baseResources[msg.sender], 99), baseResources[msg.sender]);

        address currentPlayer1 = matchmaker[0];
        if (currentPlayer1 == address(0x0)) {
            matchmaker[0] = msg.sender;
            waitingForMatch[msg.sender] = true;
            queueStartTime[msg.sender] = block.number + 50;
        }
        else if (queueStartTime[currentPlayer1] < block.number) {
            waitingForMatch[currentPlayer1] = false;
            matchmaker[0] = msg.sender;
            waitingForMatch[msg.sender] = true;
            queueStartTime[msg.sender] = block.number + 50;
        }
        else {
            waitingForMatch[currentPlayer1] = false;
            matchmaker[1] = msg.sender;

            currentOpponent[msg.sender] = currentPlayer1;
            currentOpponent[currentPlayer1] = msg.sender;

            inGame[currentPlayer1] = true;
            inGame[msg.sender] = true;

            currentResources[currentPlayer1] = baseResources[currentPlayer1];
            currentResources[msg.sender] = baseResources[msg.sender];
        }

    }

    function setTraps(bytes calldata _trap1, bytes calldata _trap2, bytes calldata _trap3) public {
        require(inGame[msg.sender] == true);
        require(hasSetTraps[msg.sender] == false);
        euint8 trap1 = TFHE.asEuint8(_trap1);
        euint8 trap2 = TFHE.asEuint8(_trap2);
        euint8 trap3 = TFHE.asEuint8(_trap3);
        traps[msg.sender] = [trap1,trap2,trap3];
        hasSetTraps[msg.sender] = true;
    }


    function tryMine(uint8 location) public {
        address opponent = currentOpponent[msg.sender];
        euint8 resources = currentResources[msg.sender];
        require(hasSetTraps[msg.sender] == true);
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
    }



    function setNumber(bytes calldata _number) public {
        euint8 number = TFHE.asEuint8(_number);
        secretNumber[msg.sender] = number;
        success = true;
    }

    function getEpoch() public view returns (uint) {
        return ( (block.number + 50) - epochStart) / epochDivisor;
    }

/*

    function mine(bytes calldata _location) public {
        uint epoch = getEpoch();
        euint8 location = TFHE.asEuint8(_location);
        euint16 availableResources = epochResource[epoch][location];
        // If location resources are 0, but not yet mined out, generate random resources
        availableResources = TFHE.cmux(epochMinedOut[epoch][location], availableResources, TFHE.randEuint16());
        // Random mine amount
        euint16 mineAmount = TFHE.div(TFHE.randEuint16(), 5);
        // Check if there are enough resources for the mine amount
        ebool enoughResources = TFHE.le(mineAmount, availableResources);
        // If there aren't enough, mine amount is reduced to the available resource amount
        mineAmount = TFHE.cmux(enoughResources, mineAmount, availableResources);
        // Subtract mine amount from resources
        availableResources = TFHE.cmux(enoughResources, TFHE.sub(availableResources, mineAmount), TFHE.sub(availableResources, availableResources));
        // If there are no resources left, the location is mined out
        epochMinedOut[epoch][location] = TFHE.eq(availableResources, 0);
        // Give player the mine amount
        playerBalance[msg.sender] = TFHE.add(playerBalance[msg.sender], mineAmount);
        // Adjust the location resources
        epochResource[epoch][location] = availableResources;

        success = true;
    }
*/

     function mine(uint8 location) public {
        uint epoch = getEpoch();
        euint16 availableResources = epochResource[epoch][location];
        // If location resources are 0, but not yet mined out, generate random resources
        availableResources = TFHE.cmux(epochMinedOut[epoch][location], availableResources, TFHE.randEuint16());
        // Random mine amount
        euint16 mineAmount = TFHE.div(TFHE.randEuint16(), 5);
        // Check if there are enough resources for the mine amount
        ebool enoughResources = TFHE.le(mineAmount, availableResources);
        // If there aren't enough, mine amount is reduced to the available resource amount
        mineAmount = TFHE.cmux(enoughResources, mineAmount, availableResources);
        // Subtract mine amount from resources
        availableResources = TFHE.cmux(enoughResources, TFHE.sub(availableResources, mineAmount), TFHE.sub(availableResources, availableResources));
        // If there are no resources left, the location is mined out
        epochMinedOut[epoch][location] = TFHE.eq(availableResources, 0);
        // Give player the mine amount
        playerBalance[msg.sender] = TFHE.add(playerBalance[msg.sender], mineAmount);
        // Adjust the location resources
        epochResource[epoch][location] = availableResources;

        success = true;
    }
    /*
    function mine2(uint8 location) public {
        uint epoch = getEpoch();
        epochResource[epoch][location] = TFHE.randEuint16();
    }
*/
     function mine2(uint8 location) public {
        uint epoch = getEpoch();
        euint16 availableResources = epochResource[epoch][location];
        ebool resourcesUnavailable = TFHE.eq(availableResources, 0);
        epochResource[epoch][location] = TFHE.cmux(resourcesUnavailable, TFHE.randEuint16(), availableResources);
    }

    function mine3() public view returns (euint16) {
        return TFHE.randEuint16();

    }

    function startMine(uint8 location) public {
        uint epoch = getEpoch();
        require(!epochMineStarted[epoch][location]);
        epochMineStarted[epoch][location] = true;
        epochResource[epoch][location] = TFHE.randEuint16();
    }

    


  }







