// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/libraries/TickMath.sol";
import "v3-core/contracts/libraries/SqrtPriceMath.sol";
import "./YYToken.sol";

interface IPancakeSwapV3Factory {
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);
}
contract NFTLockForBet is Ownable {
    // using SqrtPriceMath for uint256;
    IPancakeSwapV3Factory public factory;
    INonfungiblePositionManager public positionManager;

    IERC721 public nftContract;
    IERC20 public betToken;
    address public betTokenAddress;
    mapping(uint256 => LockInfo) public lockedNFTs;
    mapping(uint256 => address) public nftOwner;
    mapping(address => uint256[]) public lockedTokensByOwner;
    mapping(uint256 => bool) public nftClaimRewardStatus;
    uint256 maxInputNum;
    uint256 totalBetAmount = 10000 * (10 ** 18);
    uint256 lockedBetTotalValue = 0;
    uint256 public closeLockTime = 0;
    uint256 public maxLockPeriod = 3600*24*365;
    struct LockInfo {
        address owner;
        uint256 lockPeriod;
        uint256 betTokenAmount;
    }
    event NFTLocked(address indexed user, uint256 indexed tokenId);
    event CloseService(uint256 indexed blockTime);
    event OpenService(uint256 indexed blockTime);
    event RewardClaimed(
        address indexed user,
        uint256 indexed tokenId,
        uint256 amount
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner,
        uint256 indexed tokenId
    );
    constructor(
        address _nftContract,
        address _betToken,
        address _positionManager,
        address _factory
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
        nftContract = IERC721(_nftContract);
        betToken = IERC20(_betToken);
        positionManager = INonfungiblePositionManager(_positionManager);
        factory = IPancakeSwapV3Factory(_factory);
        betTokenAddress = _betToken;
        maxInputNum = 3;
    }
    function transferLockedNFTOwnership(
        uint256 tokenId,
        address newOwner
    ) external {
        require(
            lockedNFTs[tokenId].owner == msg.sender,
            "Not the owner of the locked NFT"
        );
        require(newOwner != address(0), "New owner cannot be the zero address");

        lockedNFTs[tokenId].owner = newOwner;
        _removeTokenFromOwnerEnumeration(msg.sender, tokenId);
        lockedTokensByOwner[newOwner].push(tokenId);

        emit OwnershipTransferred(msg.sender, newOwner, tokenId);
    }
    function lockNFT(
        uint256 tokenId,
        uint256 lockPeriod,
        address newOwner
    ) external {
        require(
            lockPeriod < maxLockPeriod,
            "You have to set lock period under max period limit"
        );
        require(
            nftContract.ownerOf(tokenId) == msg.sender,
            "Not the owner of the NFT"
        );
        require(closeLockTime == 0, "Lock is finished");

        nftContract.transferFrom(msg.sender, address(this), tokenId);
        uint256 betTokenAmount = getTokenAmounts(tokenId);
        lockedBetTotalValue = lockedBetTotalValue + betTokenAmount * lockPeriod;
        lockedNFTs[tokenId] = LockInfo({
            owner: msg.sender,
            lockPeriod: lockPeriod,
            betTokenAmount: betTokenAmount
        });
        lockedTokensByOwner[msg.sender].push(tokenId);
        if (newOwner != address(0)) {
            require(
                lockedNFTs[tokenId].owner == msg.sender,
                "Not the owner of the locked NFT"
            );
            lockedNFTs[tokenId].owner = newOwner;
            _removeTokenFromOwnerEnumeration(msg.sender, tokenId);
            lockedTokensByOwner[newOwner].push(tokenId);

            emit OwnershipTransferred(msg.sender, newOwner, tokenId);
        }
        nftClaimRewardStatus[tokenId] = false;
        emit NFTLocked(msg.sender, tokenId);
    }
    function lockMultipleNFTs(
        uint256[] memory tokenIds,
        uint256 lockPeriod,
        address newOwner
    ) external {
        require(closeLockTime == 0, "Lock is finished");
        require(maxInputNum >= tokenIds.length, "You have to set amounts of NFT under max available amounts");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(
                nftContract.ownerOf(tokenId) == msg.sender,
                "Not the owner of the NFT"
            );

            // Transfer the NFT to this contract
            nftContract.transferFrom(msg.sender, address(this), tokenId);

            uint256 betTokenAmount = getTokenAmounts(tokenId);
            lockedBetTotalValue =
                lockedBetTotalValue +
                betTokenAmount *
                lockPeriod;

            lockedNFTs[tokenId] = LockInfo({
                owner: msg.sender,
                lockPeriod: lockPeriod,
                betTokenAmount: betTokenAmount
            });

            lockedTokensByOwner[msg.sender].push(tokenId);

            // Transfer the locked NFT ownership
            if (newOwner != address(0)) {
                require(
                    lockedNFTs[tokenId].owner == msg.sender,
                    "Not the owner of the locked NFT"
                );
                lockedNFTs[tokenId].owner = newOwner;
                _removeTokenFromOwnerEnumeration(msg.sender, tokenId);
                lockedTokensByOwner[newOwner].push(tokenId);

                emit OwnershipTransferred(msg.sender, newOwner, tokenId);
            }
            nftClaimRewardStatus[tokenId] = false;
            emit NFTLocked(msg.sender, tokenId);
        }
    }
    function unlockNFT(uint256 tokenId) external {
        require(nftClaimRewardStatus[tokenId], "Please claim reward!");
        require(
            lockedNFTs[tokenId].owner == msg.sender,
            "Not the owner of the locked NFT"
        );
        require(
            block.timestamp >= closeLockTime + lockedNFTs[tokenId].lockPeriod &&
                closeLockTime != 0,
            "Lock period has not expired or lock is not closed"
        );

        nftContract.safeTransferFrom(address(this), msg.sender, tokenId);
        _removeTokenFromOwnerEnumeration(msg.sender, tokenId);
        delete lockedNFTs[tokenId];
    }
    function unlockMultipleNFTs(uint256[] memory tokenIds) external {
        require(maxInputNum >= tokenIds.length, "You have to set amounts of NFT under max available amounts");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(nftClaimRewardStatus[tokenId], "Please claim reward!");
            // Check if the caller is the owner of the locked NFT
            require(
                lockedNFTs[tokenId].owner == msg.sender,
                "Not the owner of the locked NFT"
            );

            // Check if the lock period has passed and the lock is closed
            require(
                block.timestamp >=
                    closeLockTime + lockedNFTs[tokenId].lockPeriod &&
                    closeLockTime != 0,
                "Lock period has not expired or lock is not closed"
            );

            // Transfer the NFT back to the original owner
            nftContract.safeTransferFrom(address(this), msg.sender, tokenId);

            // Remove the token from the owner's enumeration
            _removeTokenFromOwnerEnumeration(msg.sender, tokenId);

            // Delete the lock information
            delete lockedNFTs[tokenId];
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
        if (token0 == betTokenAddress) {
            return amount0;
        } else if (token1 == betTokenAddress) {
            return amount1;
        }
        revert("Token is not part of the pair");
    }
    function claimRewardByNftId(uint256 tokenId) external {
        require(
            !nftClaimRewardStatus[tokenId],
            "This NFT reward was already claimed"
        );
        require(
            block.timestamp >= closeLockTime + lockedNFTs[tokenId].lockPeriod &&
                closeLockTime != 0,
            "Claim too early"
        );
        uint256 betTokenAmount = getTokenAmounts(tokenId);
        uint256 tokenClaimAmount = (totalBetAmount *
            ((lockedNFTs[tokenId].lockPeriod) * (betTokenAmount))) /
            lockedBetTotalValue;
        require(tokenClaimAmount > 0, "No tokens to claim");
        SafeERC20.safeTransfer(
            betToken,
            lockedNFTs[tokenId].owner,
            tokenClaimAmount
        );
        nftClaimRewardStatus[tokenId] = true;
        emit RewardClaimed(
            lockedNFTs[tokenId].owner,
            tokenId,
            tokenClaimAmount
        );
    }
    function closeLockService() external onlyOwner {
        closeLockTime = block.timestamp;
        emit CloseService(block.timestamp);
    }
    function openLockService() external onlyOwner {
        closeLockTime = 0;
        emit OpenService(block.timestamp);
    }
    function changeLockPeriod(uint256 period) external onlyOwner {
        maxLockPeriod = period;
    }
    function changeMaxInputNum(uint256 max) external onlyOwner {
        maxInputNum = max;
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
                    mulDivRoundingUp(numerator1, numerator2, sqrtRatioBX96),
                    sqrtRatioAX96
                )
                : mulDiv(numerator1, numerator2, sqrtRatioBX96) / sqrtRatioAX96;
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
                ? mulDivRoundingUp(
                    liquidity,
                    sqrtRatioBX96 - sqrtRatioAX96,
                    FixedPoint96.Q96
                )
                : mulDiv(
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
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        uint256 prod0;
        uint256 prod1;
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Handle non-overflow cases, 256 by 256 division
        if (prod1 == 0) {
            require(denominator > 0, "denominator must be bigger than 0");
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        // Make sure the result is less than 2**256.
        // Also prevents denominator == 0
        require(denominator > prod1, "denominator must be bigger than prod1");
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        // Subtract 256 bit number from 512 bit number
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        uint256 twos = denominator & (~denominator + 1);
        // uint256 twos = -denominator & denominator;

        assembly {
            denominator := div(denominator, twos)
        }

        // Divide [prod1 prod0] by the factors of two
        assembly {
            prod0 := div(prod0, twos)
        }

        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        uint256 inv = (3 * denominator) ^ 2;

        inv *= 2 - denominator * inv; // inverse mod 2**8
        inv *= 2 - denominator * inv; // inverse mod 2**16
        inv *= 2 - denominator * inv; // inverse mod 2**32
        inv *= 2 - denominator * inv; // inverse mod 2**64
        inv *= 2 - denominator * inv; // inverse mod 2**128
        inv *= 2 - denominator * inv; // inverse mod 2**256

        result = prod0 * inv;
        return result;
    }
    function mulDivRoundingUp(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        result = mulDiv(a, b, denominator);
        if (mulmod(a, b, denominator) > 0) {
            require(result < type(uint256).max, "result is too large");
            result++;
        }
    }
}
