// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IWlpManager {
    function wlp() external view returns (address);
    // function usdw() external view returns (address);
    // function vault() external view returns (IVault);
    // function cooldownDuration() external returns (uint256);
    // function getAumInUsdw(bool maximise) external view returns (uint256);
    // function lastAddedAt(address _account) external returns (uint256);
    function addLiquidity(address _token, uint256 _amount, uint256 _minUsdw, uint256 _minWlp) external returns (uint256);
    function addLiquidityForAccount(address _fundingAccount, address _account, address _token, uint256 _amount, uint256 _minUsdw, uint256 _minWlp) external returns (uint256);
    // function removeLiquidity(address _tokenOut, uint256 _wlpAmount, uint256 _minOut, address _receiver) external returns (uint256);
    // function removeLiquidityForAccount(address _account, address _tokenOut, uint256 _wlpAmount, uint256 _minOut, address _receiver) external returns (uint256);
    // function setCooldownDuration(uint256 _cooldownDuration) external;
    // function getAum(bool _maximise) external view returns(uint256);
    // function getPriceWlp(bool _maximise) external view returns(uint256);
    // function getPriceWLPInUsdw(bool _maximise) external view returns(uint256);
    // function circuitBreakerTrigger(address _token) external;
    // function aumDeduction() external view returns(uint256);
    // function reserveDeduction() external view returns(uint256);

    // function maxPercentageOfWagerFee() external view returns(uint256);
    // function addLiquidityFeeCollector(
    //     address _token, 
    //     uint256 _amount, 
    //     uint256 _minUsdw, 
    //     uint256 _minWlp) external returns (uint256 wlpAmount_);


    // /*==================== Events *====================*/
    // event AddLiquidity(
    //     address account,
    //     address token,
    //     uint256 amount,
    //     uint256 aumInUsdw,
    //     uint256 wlpSupply,
    //     uint256 usdwAmount,
    //     uint256 mintAmount
    // );

    // event RemoveLiquidity(
    //     address account,
    //     address token,
    //     uint256 wlpAmount,
    //     uint256 aumInUsdw,
    //     uint256 wlpSupply,
    //     uint256 usdwAmount,
    //     uint256 amountOut
    // );

    // event PrivateModeSet(
    //     bool inPrivateMode
    // );

    // event HandlerEnabling(
    //     bool setting
    // );

    // event HandlerSet(
    //     address handlerAddress,
    //     bool isActive
    // );

    // event CoolDownDurationSet(
    //     uint256 cooldownDuration
    // );

    // event AumAdjustmentSet(
    //     uint256 aumAddition,
    //     uint256 aumDeduction
    // );

    // event MaxPercentageOfWagerFeeSet(
    //     uint256 maxPercentageOfWagerFee
    // );

    // event CircuitBreakerTriggered(
    //     address forToken,
    //     bool pausePayoutsOnCB,
    //     bool pauseSwapOnCB,
    //     uint256 reserveDeductionOnCB
    // );

    // event CircuitBreakerPolicy(
    //     bool pausePayoutsOnCB,
    //     bool pauseSwapOnCB,
    //     uint256 reserveDeductionOnCB
    // );

    // event CircuitBreakerReset(
    //     bool pausePayoutsOnCB,
    //     bool pauseSwapOnCB,
    //     uint256 reserveDeductionOnCB
    // );
}