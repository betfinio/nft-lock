// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/libraries/TickMath.sol";
import "v3-core/contracts/libraries/SqrtPriceMath.sol";
import "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "./FullMath.sol";

contract NFTLockForBet is Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant maxLockPeriod = 3650 days;
    uint256 public constant minLockPeriod = 30 days;

    IUniswapV3Factory public immutable factory;
    INonfungiblePositionManager public immutable positionManager;
    IERC721 public immutable nftContract;
    IERC20 public immutable betToken;

    mapping(uint256 => LockInfo) public lockedNFTs;
    mapping(uint256 => address) public nftOwner;
    mapping(address => uint256[]) public lockedTokensByOwner;
    mapping(uint256 => bool) public nftClaimRewardStatus;

    uint256 public immutable airdrop;

    uint256 public totalShares = 0;
    uint256 public closeLockTime = 0;
    struct LockInfo {
        address owner;
        uint256 lockPeriod;
        uint256 share;
        bool claimed;
    }

    event Locked(address indexed user, uint256 indexed tokenId);
    event Closed(uint256 indexed blockTime);
    event Claimed(
        address indexed user,
        uint256 indexed tokenId,
        uint256 indexed amount
    );

    modifier isOpen() {
        require(closeLockTime == 0, "Lock is finished");
        _;
    }
    modifier isClosed() {
        require(closeLockTime > 0, "Not locked yet");
        _;
    }

    constructor(
        address _nftContract,
        address _betToken,
        address _positionManager,
        address _factory,
        uint256 _airdrop
    ) Ownable(msg.sender) {
        require(
            _nftContract != address(0),
            "Nft Contract cannot be the zero address"
        );
        require(
            _betToken != address(0),
            "betToken address cannot be the zero address"
        );
        require(
            _positionManager != address(0),
            "NFT PositionManager cannot be the zero address"
        );
        require(
            _factory != address(0),
            "Factory contract address cannot be the zero address"
        );
        require(_airdrop > 0, "Total bet amount has to be greater than 0");
        nftContract = IERC721(_nftContract);
        betToken = IERC20(_betToken);
        positionManager = INonfungiblePositionManager(_positionManager);
        factory = IUniswapV3Factory(_factory);
        airdrop = _airdrop;
    }

    function lockNFT(
        uint256 tokenId,
        uint256 lockPeriod,
        address newOwner
    ) external isOpen {
        // Check if the lock period is within the limits
        require(
            lockPeriod <= maxLockPeriod,
            "You have to set lock period under max period limit"
        );
        require(
            lockPeriod >= minLockPeriod,
            "You have to set lock period over min period limit"
        );
        // Check if the caller is the owner of the NFT
        require(
            nftContract.ownerOf(tokenId) == _msgSender(),
            "Not the owner of the NFT"
        );
        // get the amount of bet token luquiditied in the NFT
        uint256 tokenLocked = getTokenAmounts(tokenId);
        // increment total locked bet amount
        totalShares += tokenLocked * lockPeriod;
        // Transfer the NFT to this contract
        nftContract.transferFrom(_msgSender(), address(this), tokenId);
        // create lock info
        lockedNFTs[tokenId] = LockInfo({
            owner: newOwner,
            lockPeriod: lockPeriod,
            share: tokenLocked * lockPeriod,
            claimed: false
        });
        // save token to owner
        lockedTokensByOwner[newOwner].push(tokenId);
        // emit event
        emit Locked(_msgSender(), tokenId);
    }

    function lockMultipleNFTs(
        uint256[] calldata tokenIds,
        uint256[] calldata lockPeriods,
        address[] calldata newOwners
    ) external isOpen {
        require(
            tokenIds.length == lockPeriods.length &&
                tokenIds.length == newOwners.length,
            "Input lengths do not match"
        );
        require(tokenIds.length > 0, "No tokens to lock");
        require(tokenIds.length <= 100, "Too many tokens to lock");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 lockPeriod = lockPeriods[i];
            address newOwner = newOwners[i];
            require(
                nftContract.ownerOf(tokenId) == _msgSender(),
                "Not the owner of the NFT"
            );
            // get the amount of bet token luquiditied in the NFT
            uint256 tokenLocked = getTokenAmounts(tokenId);
            // increment total locked bet amount
            totalShares += tokenLocked * lockPeriod;
            // Transfer the NFT to this contract
            nftContract.transferFrom(_msgSender(), address(this), tokenId);
            // create lock info
            lockedNFTs[tokenId] = LockInfo({
                owner: newOwner,
                lockPeriod: lockPeriod,
                share: tokenLocked * lockPeriod,
                claimed: false
            });
            // save token to owner
            lockedTokensByOwner[newOwner].push(tokenId);
            // emit event
            emit Locked(_msgSender(), tokenId);
        }
    }

    function claimNFT(uint256 tokenId) external isClosed {
        LockInfo memory lockInfo = lockedNFTs[tokenId];
        require(!lockInfo.claimed, "Already claimed");
        require(
            lockInfo.owner == _msgSender(),
            "Not the owner of the locked NFT"
        );
        uint256 unlockTime = lockInfo.lockPeriod + closeLockTime;
        require(
            block.timestamp >= unlockTime,
            "Lock period has not expired yet"
        );
        lockInfo.claimed = true;
        uint256 reward = (lockInfo.share / totalShares) * airdrop;
        nftContract.safeTransferFrom(address(this), _msgSender(), tokenId);
        require(betToken.transfer(_msgSender(), reward), "Transfer failed");
        emit Claimed(_msgSender(), tokenId, reward);
    }

    function claimNFTs(uint256[] calldata tokenIds) external isClosed {
        require(tokenIds.length > 0, "No tokens to claim");
        require(tokenIds.length > 100, "Too many tokens to claim");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            LockInfo memory lockInfo = lockedNFTs[tokenId];
            require(!lockInfo.claimed, "Already claimed");
            require(
                lockInfo.owner == _msgSender(),
                "Not the owner of the locked NFT"
            );
            uint256 unlockTime = lockInfo.lockPeriod + closeLockTime;
            require(
                block.timestamp >= unlockTime,
                "Lock period has not expired yet"
            );
            lockInfo.claimed = true;
            uint256 reward = (lockInfo.share / totalShares) * airdrop;
            nftContract.safeTransferFrom(address(this), _msgSender(), tokenId);
            require(betToken.transfer(_msgSender(), reward), "Transfer failed");
            emit Claimed(_msgSender(), tokenId, reward);
        }
    }

    function getTokenAmounts(uint256 tokenId) public view returns (uint256) {
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = positionManager.positions(tokenId);

        address poolAddress = factory.getPool(token0, token1, fee);
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        (uint256 amount0, uint256 amount1) = getAmountsForLiquidity(
            sqrtPriceX96,
            tickLower,
            tickUpper,
            liquidity
        );
        if (token0 == address(betToken)) {
            return amount0;
        } else if (token1 == address(betToken)) {
            return amount1;
        }
        revert("Token is not part of the pair");
    }

    function closeLockService() external onlyOwner {
        closeLockTime = block.timestamp;
        require(
            betToken.balanceOf(address(this)) >= airdrop,
            "Balance is insufficient"
        );
        emit Closed(block.timestamp);
    }

    function _removeTokenFromOwnerEnumeration(
        address owner,
        uint256 tokenId
    ) internal {
        uint256 lastTokenIndex = lockedTokensByOwner[owner].length - 1;
        uint256 tokenIndex;

        // Find the token index in the array
        for (uint256 i = 0; i < lockedTokensByOwner[owner].length; i++) {
            if (lockedTokensByOwner[owner][i] == tokenId) {
                tokenIndex = i;
                break;
            }
        }

        // If the token being removed is not the last one, swap it with the last one
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = lockedTokensByOwner[owner][lastTokenIndex];
            lockedTokensByOwner[owner][tokenIndex] = lastTokenId;
        }

        lockedTokensByOwner[owner].pop();
    }

    function getAmountsForLiquidity(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        if (sqrtPriceX96 <= sqrtRatioAX96) {
            amount0 = getAmount0Delta(
                sqrtRatioAX96,
                sqrtRatioBX96,
                liquidity,
                true
            );
        } else if (sqrtPriceX96 < sqrtRatioBX96) {
            amount0 = getAmount0Delta(
                sqrtPriceX96,
                sqrtRatioBX96,
                liquidity,
                true
            );
            amount1 = getAmount1Delta(
                sqrtRatioAX96,
                sqrtPriceX96,
                liquidity,
                true
            );
        } else {
            amount1 = getAmount1Delta(
                sqrtRatioAX96,
                sqrtRatioBX96,
                liquidity,
                true
            );
        }
    }

    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;
        uint256 numerator2 = sqrtRatioBX96 - sqrtRatioAX96;

        require(sqrtRatioAX96 > 0, "sqrtRatioAX96 value must bigger than 0");

        return
            roundUp
                ? divRoundingUp(
                    FullMath08.mulDivRoundingUp(
                        numerator1,
                        numerator2,
                        sqrtRatioBX96
                    ),
                    sqrtRatioAX96
                )
                : FullMath08.mulDiv(numerator1, numerator2, sqrtRatioBX96) /
                    sqrtRatioAX96;
    }

    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return
            roundUp
                ? FullMath08.mulDivRoundingUp(
                    liquidity,
                    sqrtRatioBX96 - sqrtRatioAX96,
                    FixedPoint96.Q96
                )
                : FullMath08.mulDiv(
                    liquidity,
                    sqrtRatioBX96 - sqrtRatioAX96,
                    FixedPoint96.Q96
                );
    }

    function divRoundingUp(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256 z) {
        assembly {
            z := add(div(x, y), gt(mod(x, y), 0))
        }
    }
}
