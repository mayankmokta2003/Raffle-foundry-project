// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {CodeConstants} from "../../script/HelperConfig.s.sol";

contract RaffleTest is Test , CodeConstants  {
    Raffle public raffle;
    HelperConfig public helperConfig;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    uint256 enteranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;
    address link;
    address account;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        // as deployRaffle returns (raffle , helperConfig)
        (raffle, helperConfig) = deployer.DeployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        enteranceFee = config.enteranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testRaffleInetializesInOpenState() external view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    // function testRaffleRevertsWhenYouDontPayMore() external {
    //     vm.prank(PLAYER);
    //     vm.expectRevert(Raffle.Raffle__sendMoreToEnterRaffle.selector);
    //     raffle.enterRaffle();
    // }

    function testRaffleRevertsWhenYouDontPayMore() external {
        vm.prank(PLAYER);
        vm.expectRevert();
        raffle.enterRaffle();
    }

    function testRaffleRecordsWhenTheyEnter() public {
        vm.prank(PLAYER);

        raffle.enterRaffle{value: enteranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnteringRaffleEmitsEvent() public {
        // in order to test events we have to write them in this file as well
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
    }

    function testDontAllowPlayersToEnterRaffleWhileRaffleCalculation() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        // used to change the time to whatever we want
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number);
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
    }

    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number);

        (bool upkeepNeeded ,) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfItIsNotOpen() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number);
        raffle.performUpkeep("");

        (bool upkeepNeeded ,) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfEnoughTimeHasPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();

        (bool upkeepNeeded ,) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    // PERFORM UPKEEPS

    function testPerformUpKeepCanOnlyRunIfCheckUpKeepIsTrue() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number);

        raffle.performUpkeep("");

    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 players = 0;
        uint256 balance = 0;
        Raffle.RaffleState rstate = raffle.getRaffleState();

        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle_UpKeepNotNeeded.selector , players , balance , rstate));
            raffle.performUpkeep("");
    }

    modifier raffleEntered {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        vm.warp(block.timestamp + interval +1);
        vm.roll(block.number);
        _;
    }

    function testPerformUpKeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered{

        // this recordlogs says whatever logs is in performupkeep record them in an array and we record them in entries array
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256 (requestId) > 0);
        assert(uint256 (raffleState) > 0);

    }

    // FULFILL RANDOM WORDS

    modifier skipFork() {
        if(block.chainid == LOCAL_CHAIN_ID){
        return;
    }
    _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public raffleEntered skipFork{
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId , address(raffle));

    }
    
    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEntered skipFork{
        // ARRANGE
        uint256 additionalEnterance = 3;
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for(uint256 i = startingIndex ; i < additionalEnterance + startingIndex ; i++){
            address newPlayer = address(uint160(i));
            hoax(newPlayer , 1 ether);
            raffle.enterRaffle{value: enteranceFee}();
        }
        uint256 startingTimestamp = raffle.getLastTimestamp();
        uint256 winnerStartingBalance = expectedWinner.balance;
        // ACT

        // generating random number and saving it in an array

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId) , address(raffle));

        // ASSERT
        // here we will get the winner and send money to winner

        address winner = raffle.getRecentWinner();
        uint256 winnerBalance = winner.balance;
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 endingTimeStamp = raffle.getLastTimestamp();
        uint256 prizeMoney = enteranceFee * (additionalEnterance + 1);

        assert(endingTimeStamp > startingTimestamp);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prizeMoney);
        assert(expectedWinner == winner);


    }


}
