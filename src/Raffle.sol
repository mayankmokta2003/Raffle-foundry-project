// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title A simple Raffle contract
 * @author Mayank Mokta
 * @notice This contract is for creating a simple Raffle
 * @dev Implements chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {

    /* Errors */
    error Raffle__sendMoreToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();


    enum RaffleState {
        OPEN,        /* 0 */
        CALCULATING       /* 1 */
    }


    /* State variables */
    uint16 private constant REQUEST_CONFIRMATION = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_enteranceFee;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    
    // we made address payable in order to pay the prize to on of the address in players
    address payable[] private s_players;
    address private s_recentWinner;
    uint256 private s_lastTimeStamp;
    RaffleState private s_raffleState;

    /* Events */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    constructor(
        uint256 enteranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_enteranceFee = enteranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {

        if(s_raffleState != RaffleState.OPEN){
            revert Raffle__RaffleNotOpen();
        }

        if (msg.value < i_enteranceFee) {
            revert Raffle__sendMoreToEnterRaffle();
        }
        s_players.push(payable(msg.sender));
        // these events makes migration easier and makes frontend indexing easier
        // we first use events and the emit
        emit RaffleEntered(msg.sender);
    }

    // get a random number
    // through a random number select a player
    // be automatically called
    function pickWinner() external {
        // to check if enough time has passed or not
        if ((block.timestamp - s_lastTimeStamp) < i_interval) {
            revert();
        }

        // get out random
        s_raffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash,
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATION,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(
                // set nativepayment to true to pay for VRF requests with sepolia ETH intead of LINK
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
        });

        
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
        request
        );
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal virtual override {
       uint256 indexOfWinner = randomWords[0] % s_players.length;
       address payable recentWinner = s_players[indexOfWinner];
       s_recentWinner = recentWinner;

       s_raffleState = RaffleState.OPEN;
       s_players = new address payable[](0);
       s_lastTimeStamp = block.timestamp;
       emit WinnerPicked(s_recentWinner);

       (bool success ,) = s_recentWinner.call{value: address(this).balance}("");
       if(!success){
        revert Raffle__TransferFailed();
       }
    }

    /**
     * Getter Functions *
     */
    function getEnteranceFee() external view returns (uint256) {
        return i_enteranceFee;
    }
}
