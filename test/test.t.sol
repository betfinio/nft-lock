// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/NFTLockForBet.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
contract MyContractTest is Test {
    NFTLockForBet public nftLockForBet;
    address public owner;
    address public user1;
    address public user;
    uint256[]  tokenIds;
    uint256 public closeTime;
    IERC721 public nftContract;
    IERC20 public betTokenContract;
    function setUp() public {
        owner = 0xE3D14216CC2fc7332538B3Cf7E9cc1f437BA0540;
        user = 0xE3D14216CC2fc7332538B3Cf7E9cc1f437BA0540;
        user1 = 0xb19b83eA23a65749900F4394597a77949247b2cd;
        tokenIds = [2103052, 2103068];
        uint256 forkId = vm.createFork("https://polygon.drpc.org");
        vm.selectFork(forkId);
        nftLockForBet = new NFTLockForBet(
            0xC36442b4a4522E871399CD717aBDD847Ab11FE88,
            0xaBde7226731Ab38236e9615F1cCF5B1088B86505,
            0xC36442b4a4522E871399CD717aBDD847Ab11FE88,
            0x1F98431c8aD98523631AE4a59f267346ea31F984
        );
        nftContract = IERC721(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
        betTokenContract = IERC20(0xaBde7226731Ab38236e9615F1cCF5B1088B86505);

    }

    function testlockContract() public {
        //transfer reward tokens to contract
        vm.startPrank(owner);
        betTokenContract.transfer(address(nftLockForBet), 10000* 10 ** 18);
        vm.stopPrank(); 
        //simulate with user
        vm.startPrank(user);
        nftContract.approve(address(nftLockForBet), 2103052);
        nftContract.approve(address(nftLockForBet), 2103068);
        //lock multi NFTs and transfer ownership to user1
        nftLockForBet.lockMultipleNFTs(tokenIds, 3000, user1);
        vm.stopPrank(); 
        //close lock service
        nftLockForBet.closeLockService();
        closeTime = block.timestamp;
        vm.warp(block.timestamp + 6000);
        assertEq(block.timestamp, closeTime + 6000);
        //user1 claim reward
        vm.startPrank(user1);
        nftLockForBet.claimRewardByNftId(2103068);
        vm.stopPrank(); 
        //user1 unlock multiple nfts
        vm.startPrank(user1);
        nftLockForBet.unlockMultipleNFTs(tokenIds);
        vm.stopPrank(); 
    }
}
