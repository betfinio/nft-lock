// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/NFTLockForBet.sol";
import "./NFT.sol";

contract MyContractTest is Test {
    NFTLockForBet public nftLockForBet;
    NFT public nft;
    address public positionManager = address(888);
    address public factory = address(999);
    address public bet = address(666);

    address public alice = address(1);

    function setUp() public {
        nft = new NFT();
        nftLockForBet = new NFTLockForBet(
            address(nft),
            bet,
            positionManager,
            factory,
            1_000_000 ether
        );

        nft.mint(alice, 1);
        setAmountForTokenId(1, 1_000 ether);
    }

    function setAmountForTokenId(uint256 tokenId, uint256 amount) internal {
        vm.mockCall(
            address(nftLockForBet),
            abi.encodeWithSelector(
                NFTLockForBet.getTokenAmounts.selector,
                uint256(tokenId)
            ),
            abi.encode(amount)
        );
    }

    function test_lock() public {
        vm.startPrank(alice);
        nft.approve(address(nftLockForBet), 1);
        // nftLockForBet.lockNFT(1, 30 days, alice);
    }
}
