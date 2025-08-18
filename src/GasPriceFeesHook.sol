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
        if(!_key.fee.isDynamicFees()) {
            revert GasPriceFeesHook__MustUseDynamicFee();
        }

        return this.beforeInitialize.selector;
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    ) internal view override returns (bytes4, BeforeSwapDelta, uint24) {
        // TODO

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address,
        PoolKey calldata,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        // TODO

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
}