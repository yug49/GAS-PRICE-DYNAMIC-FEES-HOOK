// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-periphery/lib/v4-core/src/libraries/Hooks.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";
import {PoolKey} from "v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-periphery/lib/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {IPoolManager} from "v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {Currency} from "v4-periphery/lib/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "v4-periphery/lib/v4-core/src/libraries/LPFeeLibrary.sol";
import {ModifyLiquidityParams} from "v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-periphery/lib/v4-core/src/types/BeforeSwapDelta.sol";

contract GasPriceFeesHook is BaseHook {

    using LPFeeLibrary for uint24;

    error GasPriceFeesHook__MustUseDynamicFee();

    // keeping track of the moving average been updated?
    uint128 public movingAverageGasPrice;

    // how many times has the moving avg been updated?
    // needed as the denominator to update it the next time based on the moving avg formula
    uint104 public movingAverageGasPriceCount;

    // the default base fees we will charge
    uint24 public constant BASE_FEE = 5000; // 0.5%

    constructor (address _poolManager) BaseHook(IPoolManager(_poolManager)) {
        _updateMovingAverage();
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * In before initalize we need to ensure that the pool being added is with the dynamic fees
     * This prevents user adding pools with the static fees(if passed then the dynamic feature, later made will be ignored by the uniswap)
     */
    function _beforeInitialize(
        address _sender,
        PoolKey calldata _key,
        uint160 _sqrtPriceX96
    ) internal pure override returns (bytes4) {
        // Ensure that the fees passed is dynamic
        if(!_key.fee.isDynamicFee()) {
            revert GasPriceFeesHook__MustUseDynamicFee();
        }

        return this.beforeInitialize.selector;
    }

    function _beforeSwap(
        address _sender,
        PoolKey calldata key,
        SwapParams calldata _swapParams,
        bytes calldata _hookData
    ) internal view override returns (bytes4, BeforeSwapDelta, uint24) {
        // We need to capture the fees that we will be charging, based on gas prices
        uint24 fee = _getFee();

        // Set the fee with our override flag
        uint24 feeWithFlag = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;

        // the fee is relevant to the amountSpecified in the swap
        // if the amountSpecified is negative and zeroForOne is true then we are swapping 0 -> 1 and the fee is calculated by the input token
        // if i come to an ETH <> Token pool
        // I will be paying 0.01 ETH as fees for each 1 ETH swap from this pool

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address,
        PoolKey calldata,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        // Update our moving average gas price
        _updateMovingAverage();

        return (this.afterSwap.selector, 0);
    }

    // Update our moving avg gas price
    function _updateMovingAverage() internal {
        // Get the gas price of the transaction
        uint128 gasPrice = uint128(tx.gasprice);

        // New avg = (old avg * # transactions tracked * currency gas price) / (% of transactions tracked + 1)
        movingAverageGasPrice = 
            ((movingAverageGasPrice * movingAverageGasPriceCount) + gasPrice) / (movingAverageGasPriceCount + 1);

        // Increment the count of transactions tracked
        movingAverageGasPriceCount++;
    }

    // Internal function that determines a fee based on the recent gas prices compared to the current gas price

    function _getFee() internal view returns (uint24) {
        // Get the current gas price
        uint256 gasPrice = tx.gasprice;
        if(gasPrice > type(uint128).max) {
            gasPrice = type(uint128).max;
        } else {
            gasPrice = uint128(tx.gasprice);
        }

        // If the gas price > movingAverageGasPrice by 10% or more, then half the fees
        if (gasPrice > movingAverageGasPrice * 11 / 10) {
            return BASE_FEE / 2;
        }

        // If the gas price < movingAverageGasPrice by 10% or more, then double the fees
        if (gasPrice < movingAverageGasPrice * 9 / 10) {
            return BASE_FEE * 2;
        }

        // Otherwise, return the base fee
        return BASE_FEE;
    }
}