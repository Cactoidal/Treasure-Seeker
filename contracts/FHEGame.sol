
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "fhevm/lib/TFHE.sol";

contract FHEGame {


    mapping (address => euint8) public secretNumber;
    bool public success;
    uint epochStart;
    uint constant epochDivisor = 5000;
    mapping (uint => mapping (euint8 => euint16)) public epochResource;
    mapping (uint => mapping (euint8 => ebool)) public epochMinedOut;
    mapping (address => euint32) playerBalance;

    constructor() {
        epochStart = block.number;
    }

    function setNumber(bytes calldata _number) public {
        euint8 number = TFHE.asEuint8(_number);
        secretNumber[msg.sender] = number;
        success = true;
    }

    function getEpoch() public view returns (uint) {
        return (block.number - epochStart) / epochDivisor;
    }


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
        availableResources = TFHE.sub(availableResources, mineAmount);
        // If there are no resources left, the location is mined out
        epochMinedOut[epoch][location] = TFHE.eq(availableResources, 0);
        // Give player the mine amount
        playerBalance[msg.sender] = TFHE.add(playerBalance[msg.sender], mineAmount);
        // Adjust the location resources
        epochResource[epoch][location] = availableResources;
    }


  }







