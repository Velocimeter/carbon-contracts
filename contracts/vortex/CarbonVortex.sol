// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ICarbonVortex } from "./interfaces/ICarbonVortex.sol";
import { IVersioned } from "../utility/interfaces/IVersioned.sol";
import { IVault } from "../utility/interfaces/IVault.sol";
import { ICarbonController } from "../carbon/interfaces/ICarbonController.sol";
import { Upgradeable } from "../utility/Upgradeable.sol";
import { Token, NATIVE_TOKEN } from "../token/Token.sol";
import { Utils } from "../utility/Utils.sol";
import { MathEx } from "../utility/MathEx.sol";
import { ExpDecayMath } from "../utility/ExpDecayMath.sol";
import { PPM_RESOLUTION, MAX_GAP } from "../utility/Constants.sol";

/**
 * @notice CarbonVortex contract
 *
 * @dev
 *
 * collects fees and allows users to trade tokens in a dutch auction style
 * configurable parameters include the target token, final target token and the halflife
 * auctions are initiated by calling the execute function
 * all auctions start with an initial price of 2^128 - 1
 * half-life parameter sets the price decay rate -
 * - this is the time in seconds it takes for the price to halve
 * - this parameter can be configured so that tokens reach the market rate faster or slower
 * target token is the token to which all other tokens are traded to (can be native token for example)
 * final target token is an additional token to which the target token is traded to (optional)
 * transferAddress is the address to which all target / final target tokens are sent to
 */
contract CarbonVortex is ICarbonVortex, Upgradeable, ReentrancyGuardUpgradeable, Utils {
    using Address for address payable;
    using SafeCast for uint256;

    uint128 private constant INITIAL_PRICE_SOURCE_AMOUNT = type(uint128).max;
    uint128 private constant INITIAL_PRICE_TARGET_AMOUNT = 1e12;

    // addresses for token withdrawal
    ICarbonController private immutable _carbonController;
    IVault private immutable _vault;

    // first token for swapping
    Token private immutable _targetToken;
    // second (optional) token for swapping
    Token private immutable _finalTargetToken;

    // total target (if no finalTarget token is defined) / finalTarget tokens collected in transferAddress
    uint256 private _totalCollected;

    // rewards ppm (points per million) - used to calculate rewards for the caller
    uint32 private _rewardsPPM;

    // price reset multiplier - used to reset the price after a trade in special cases
    uint32 private _priceResetMultiplier;

    // min token sale amount multiplier - used to reset the price after execute in special cases
    uint32 private _minTokenSaleAmountMultiplier;

    // time until the price gets halved for the target token during a trade
    uint32 private _targetTokenPriceDecayHalfLife;

    // time until the price gets halved for the target token on price reset during a trade
    uint32 private _targetTokenPriceDecayHalfLifeOnReset;

    // time until the price gets halved for all tokens when auction is initialized
    uint32 private _priceDecayHalfLife;

    // token to pair disabled mapping (disabled pairs aren't tradeable)
    mapping(Token token => bool pairDisabled) private _disabledPairs;

    // token to trading start time mapping
    mapping(Token token => uint32 tradingStartTime) private _tradingStartTimes;

    // token to initial price mapping
    mapping(Token token => Price initialPrice) private _initialPrice;

    // min token sale amounts - resets the token price if below this amount after a call to execute
    // resets the current sale amount if below this amount after a trade (for target token)
    mapping(Token token => uint128 _minTokenSaleAmount) private _minTokenSaleAmounts;

    // initial and current target token sale amount - for targetToken->finalTargetToken trades
    SaleAmount private _targetTokenSaleAmount;

    // address for token collection - collects all swapped target/final target tokens
    address payable private _transferAddress;

    address payable private _tank;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP - 9] private __gap;

    /**
     * @dev used to set immutable state variables
     */
    constructor(
        ICarbonController carbonController,
        IVault vault,
        Token targetTokenInit,
        Token finalTargetTokenInit
    ) validAddress(Token.unwrap(targetTokenInit)) {
        _carbonController = carbonController;
        _vault = vault;

        _targetToken = targetTokenInit;
        _finalTargetToken = finalTargetTokenInit;
        _disableInitializers();
    }

    /**
     * @dev fully initializes the contract and its parents
     */
    function initialize(address payable transferAddressInit) public initializer {
        __CarbonVortex_init(transferAddressInit);
    }

    // solhint-disable func-name-mixedcase

    /**
     * @dev initializes the contract and its parents
     */
    function __CarbonVortex_init(address payable transferAddressInit) internal onlyInitializing {
        __Upgradeable_init();
        __ReentrancyGuard_init();

        __CarbonVortex_init_unchained(transferAddressInit);
    }

    /**
     * @dev performs contract-specific initialization
     */
    function __CarbonVortex_init_unchained(address payable transferAddressInit) internal onlyInitializing {
        // set rewards PPM to 1000
        _setRewardsPPM(1000);
        // set price reset multiplier to 2x
        _setPriceResetMultiplier(2);
        // set min token sale amount multiplier to 4x
        _setMinTokenSaleAmountMultiplier(4);
        // set price decay half-life to 12 hours
        _setPriceDecayHalfLife(12 hours);
        // set target token price decay half-life to 12 hours
        _setTargetTokenPriceDecayHalfLife(12 hours);
        // set target token price decay half-life to 10 days
        _setTargetTokenPriceDecayHalfLifeOnReset(10 days);
        // set initial target token sale amount to 100 eth
        _setMaxTargetTokenSaleAmount(uint128(100) * uint128(10) ** _targetToken.decimals());
        // set min target token sale amount to 10 eth
        _setMinTokenSaleAmount(_targetToken, uint128(10) * uint128(10) ** _targetToken.decimals());
        // set transfer address
        _setTransferAddress(transferAddressInit);
    }

    /**
     * @notice authorize the contract to receive the native token
     */
    receive() external payable {}

    /**
     * @dev perform various validations for the token array
     */
    modifier validateTokens(Token[] calldata tokens) {
        _validateTokens(tokens);
        _;
    }

    /**
     * @dev validate token
     */
    modifier validToken(Token token) {
        _validToken(token);
        _;
    }

    /**
     * @inheritdoc Upgradeable
     */
    function version() public pure override(IVersioned, Upgradeable) returns (uint16) {
        return 4;
    }

    /**
     * @notice sets the rewards ppm
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setRewardsPPM(uint32 newRewardsPPM) external onlyAdmin validFee(newRewardsPPM) {
        _setRewardsPPM(newRewardsPPM);
    }

    /**
     * @notice sets the price reset multiplier
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setPriceResetMultiplier(
        uint32 newPriceResetMultiplier
    ) external onlyAdmin greaterThanZero(newPriceResetMultiplier) {
        _setPriceResetMultiplier(newPriceResetMultiplier);
    }

    /**
     * @notice sets the minimum token sale amount multiplier
     *
     * Requirements:
     *
     * - The caller must be the admin of the contract.
     */
    function setMinTokenSaleAmountMultiplier(
        uint32 newMinTokenSaleAmountMultiplier
    ) external onlyAdmin greaterThanZero(newMinTokenSaleAmountMultiplier) {
        _setMinTokenSaleAmountMultiplier(newMinTokenSaleAmountMultiplier);
    }

    /**
     * @notice sets the price decay half-life for all tokens except target
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setPriceDecayHalfLife(
        uint32 newPriceDecayHalfLife
    ) external onlyAdmin greaterThanZero(newPriceDecayHalfLife) {
        _setPriceDecayHalfLife(newPriceDecayHalfLife);
    }

    /**
     * @notice sets the price decay half-life for the target token
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setTargetTokenPriceDecayHalfLife(
        uint32 newPriceDecayHalfLife
    ) external onlyAdmin greaterThanZero(newPriceDecayHalfLife) {
        _setTargetTokenPriceDecayHalfLife(newPriceDecayHalfLife);
    }

    /**
     * @notice sets the price decay half-life for the target token on reset
     *
     * Requirements:
     *
     * - The caller must be the admin of the contract.
     */
    function setTargetTokenPriceDecayHalfLifeOnReset(
        uint32 newPriceDecayHalfLife
    ) external onlyAdmin greaterThanZero(newPriceDecayHalfLife) {
        _setTargetTokenPriceDecayHalfLifeOnReset(newPriceDecayHalfLife);
    }

    /**
     * @notice sets the max (or initial) target token sale amount
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setMaxTargetTokenSaleAmount(
        uint128 newMaxTargetTokenSaleAmount
    ) external onlyAdmin greaterThanZero(newMaxTargetTokenSaleAmount) {
        _setMaxTargetTokenSaleAmount(newMaxTargetTokenSaleAmount);
    }

    /**
     * @notice sets the min target token sale amount
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setMinTargetTokenSaleAmount(
        uint128 newMinTargetTokenSaleAmount
    ) external onlyAdmin greaterThanZero(newMinTargetTokenSaleAmount) {
        _setMinTokenSaleAmount(_targetToken, newMinTargetTokenSaleAmount);
    }

    /**
     * @notice sets if trading is enabled or disabled for a token
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function disablePair(Token token, bool disabled) external onlyAdmin {
        _setPairDisabled(token, disabled);
    }

    /**
     * @notice sets the transfer address
     *
     * requirements:
     *
     * - the caller must be the current admin of the contract
     */
    function setTransferAddress(address newTransferAddress) external onlyAdmin {
        _setTransferAddress(newTransferAddress);
    }

    /**
     * @dev withdraws funds held by the contract and sends them to an account
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function withdrawFunds(
        Token[] calldata tokens,
        address payable target,
        uint256[] calldata amounts
    ) external validAddress(target) validateTokens(tokens) nonReentrant onlyAdmin {
        uint256 len = tokens.length;
        if (len != amounts.length) {
            revert InvalidAmountLength();
        }
        for (uint256 i = 0; i < len; i = uncheckedInc(i)) {
            // safe due to nonReentrant modifier (forwards all available gas in case of ETH)
            tokens[i].unsafeTransfer(target, amounts[i]);
        }

        emit FundsWithdrawn({ tokens: tokens, caller: msg.sender, target: target, amounts: amounts });
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function rewardsPPM() external view returns (uint32) {
        return _rewardsPPM;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function totalCollected() external view returns (uint256) {
        return _totalCollected;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function targetToken() external view returns (Token) {
        return _targetToken;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function finalTargetToken() external view returns (Token) {
        return _finalTargetToken;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function transferAddress() external view returns (address) {
        return _transferAddress;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function availableTokens(Token token) external view returns (uint256) {
        uint256 totalFees = 0;
        if (address(_carbonController) != address(0)) {
            totalFees += _carbonController.accumulatedFees(token);
        }
        if (address(_vault) != address(0)) {
            totalFees += token.balanceOf(address(_vault));
        }
        return totalFees + token.balanceOf(address(this));
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function tank() external view returns (address payable) {
        return _tank;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function setTank(address payable newTank) external onlyAdmin validAddress(newTank) {
        address prevTank = _tank;
        if (prevTank == newTank) {
            return;
        }

        _tank = newTank;
        emit TankSet({ prevTank: prevTank, newTank: newTank });
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function execute(Token[] calldata tokens) external nonReentrant validateTokens(tokens) {
        uint256 len = tokens.length;

        // allocate array for the fee amounts for the tokens
        uint256[] memory feeAmounts = new uint256[](len);
        // allocate array for the reward amounts for caller
        uint256[] memory rewardAmounts = new uint256[](len);
        // cache rewardsPPM to save gas
        uint256 rewardsPPMValue = _rewardsPPM;

        // cache address checks to save gas
        bool carbonControllerIsNotZero = address(_carbonController) != address(0);
        bool vaultIsNotZero = address(_vault) != address(0);

        // withdraw fees from carbon vault
        for (uint256 i = 0; i < len; i = uncheckedInc(i)) {
            Token token = tokens[i];
            // withdraw token fees
            uint256 totalFeeAmount = 0;
            if (carbonControllerIsNotZero) {
                totalFeeAmount += _carbonController.withdrawFees(token, type(uint256).max, address(this));
            }
            if (vaultIsNotZero) {
                // get vault token balance
                uint256 vaultBalance = token.balanceOf(address(_vault));
                // withdraw vault token balance
                _vault.withdrawFunds(token, payable(address(this)), vaultBalance);
                totalFeeAmount += vaultBalance;
            }
            feeAmounts[i] = totalFeeAmount;

            // get reward amount for token
            rewardAmounts[i] = MathEx.mulDivF(totalFeeAmount, rewardsPPMValue, PPM_RESOLUTION);
        }

        // go through all tokens and start / reset dutch auction if necessary
        for (uint256 i = 0; i < len; i = uncheckedInc(i)) {
            Token token = tokens[i];
            uint256 totalFeeAmount = feeAmounts[i];
            // get fee and reward amounts
            uint256 rewardAmount = rewardAmounts[i];
            uint256 feeAmount = totalFeeAmount - rewardAmount;
            // skip token if no fees have accumulated or token pair is disabled
            if (totalFeeAmount == 0 || _disabledPairs[token]) {
                continue;
            }
            // transfer proceeds to the transfer address for the final target token
            if (token == _finalTargetToken) {
                _transferProceeds(token, feeAmount);
                continue;
            }

            if (token == _targetToken) {
                // if _finalTargetToken is not set, directly transfer the fees to the transfer address
                if (Token.unwrap(_finalTargetToken) == address(0)) {
                    _transferProceeds(_targetToken, feeAmount);
                } else if (
                    !_tradingEnabled(token) ||
                    _amountAvailableForTrading(token) < _minTokenSaleAmounts[token] ||
                    _auctionPriceIsBelowMinimum(token)
                ) {
                    // reset trading for target token
                    _resetTradingTarget(rewardAmount);
                }
            } else {
                uint128 tradingAmount = _amountAvailableForTrading(token);
                if (
                    !_tradingEnabled(token) ||
                    tradingAmount - feeAmount < _minTokenSaleAmounts[token] ||
                    tradingAmount > _minTokenSaleAmountMultiplier * _minTokenSaleAmounts[token] ||
                    _auctionPriceIsBelowMinimum(token)
                ) {
                    // reset trading for token
                    _resetTrading(token, rewardAmount);
                }
            }
        }

        // allocate rewards to caller
        _allocateRewards(msg.sender, tokens, rewardAmounts);
    }

    /**
     * @dev resets dutch auction for target token -> TKN trades and set the initial price to max possible
     */
    function _resetTrading(Token token, uint256 rewardAmount) private {
        // reset the auction with the initial price
        Price memory price = _resetAuction(token);
        // set min token sale amount
        _setMinTokenSaleAmount(token, (token.balanceOf(address(this)) - rewardAmount).toUint128() / 2);
        emit TradingReset({ token: token, price: price });
    }

    /**
     * @dev resets dutch auction for finalTargetToken->targetToken trades and set the initial price to max possible
     */
    function _resetTradingTarget(uint256 rewardAmount) private {
        // reset the auction with the initial price
        Price memory price = _resetAuction(_targetToken);
        // reset the current target token sale amount
        _targetTokenSaleAmount.current = Math
            .min(_targetToken.balanceOf(address(this)) - rewardAmount, _targetTokenSaleAmount.initial)
            .toUint128();
        // set price decay halflife to the current price decay halflife
        _setTargetTokenPriceDecayHalfLife(_priceDecayHalfLife);
        // emit trading reset event
        emit TradingReset({ token: _targetToken, price: price });
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function priceResetMultiplier() external view returns (uint32) {
        return _priceResetMultiplier;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function minTokenSaleAmountMultiplier() external view returns (uint32) {
        return _minTokenSaleAmountMultiplier;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function priceDecayHalfLife() external view returns (uint32) {
        return _priceDecayHalfLife;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function targetTokenPriceDecayHalfLife() external view returns (uint32) {
        return _targetTokenPriceDecayHalfLife;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function targetTokenPriceDecayHalfLifeOnReset() external view returns (uint32) {
        return _targetTokenPriceDecayHalfLifeOnReset;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function targetTokenSaleAmount() external view returns (SaleAmount memory) {
        return _targetTokenSaleAmount;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function minTokenSaleAmount(Token token) external view returns (uint128) {
        return _minTokenSaleAmounts[token];
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function minTargetTokenSaleAmount() external view returns (uint128) {
        return _minTokenSaleAmounts[_targetToken];
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function pairDisabled(Token token) external view returns (bool) {
        return _disabledPairs[token];
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function tradingEnabled(Token token) external view returns (bool) {
        return _tradingEnabled(token);
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function amountAvailableForTrading(Token token) external view returns (uint128) {
        return _amountAvailableForTrading(token);
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function expectedTradeReturn(Token token, uint128 sourceAmount) external view validToken(token) returns (uint128) {
        Price memory currentPrice = tokenPrice(token);
        // revert if price is not valid
        _validPrice(currentPrice);
        // calculate the target amount based on the current price and token
        uint128 targetAmount = MathEx
            .mulDivF(currentPrice.targetAmount, sourceAmount, currentPrice.sourceAmount)
            .toUint128();
        // revert if not enough amount available for trade
        if (targetAmount > _amountAvailableForTrading(token)) {
            revert InsufficientAmountForTrading();
        }
        return targetAmount;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function expectedTradeInput(Token token, uint128 targetAmount) public view validToken(token) returns (uint128) {
        // revert if not enough amount available for trade
        if (targetAmount > _amountAvailableForTrading(token)) {
            revert InsufficientAmountForTrading();
        }
        Price memory currentPrice = tokenPrice(token);
        // revert if current price is not valid
        _validPrice(currentPrice);
        // calculate the trade input based on the current price
        return MathEx.mulDivC(currentPrice.sourceAmount, targetAmount, currentPrice.targetAmount).toUint128();
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function tokenPrice(Token token) public view returns (Price memory) {
        // cache trading start time to save gas
        uint32 tradingStartTime = _tradingStartTimes[token];
        // revert if trading hasn't been enabled for a token
        if (tradingStartTime == 0) {
            revert TradingDisabled();
        }
        // get time elapsed since trading was enabled
        uint32 timeElapsed = uint32(block.timestamp) - tradingStartTime;
        // get initial price as set by resetTrading
        Price memory price = _initialPrice[token];
        // get the halflife for the token
        uint32 currentPriceDecayHalfLife = token == _targetToken ? _targetTokenPriceDecayHalfLife : _priceDecayHalfLife;
        // get the current price by adjusting the amount with the exp decay formula
        price.sourceAmount = ExpDecayMath
            .calcExpDecay(price.sourceAmount, timeElapsed, currentPriceDecayHalfLife)
            .toUint128();
        // return the price
        return price;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function trade(
        Token token,
        uint128 targetAmount,
        uint128 maxInput
    ) external payable nonReentrant validToken(token) greaterThanZero(targetAmount) {
        uint128 sourceAmount;
        if (token == _targetToken) {
            sourceAmount = _sellTargetForFinalTarget(targetAmount, maxInput);
        } else {
            sourceAmount = _sellTokenForTargetToken(token, targetAmount, maxInput);
        }
        emit TokenTraded({ caller: msg.sender, token: token, sourceAmount: sourceAmount, targetAmount: targetAmount });
    }

    function _sellTokenForTargetToken(Token token, uint128 targetAmount, uint128 maxInput) private returns (uint128) {
        uint128 sourceAmount = expectedTradeInput(token, targetAmount);
        // revert if trade requires 0 target token
        if (sourceAmount == 0) {
            revert InvalidTrade();
        }
        // revert if trade requires more than maxInput
        if (sourceAmount > maxInput) {
            revert GreaterThanMaxInput();
        }
        // revert if unnecessary native token is received
        if (_targetToken != NATIVE_TOKEN && msg.value > 0) {
            revert UnnecessaryNativeTokenReceived();
        }
        // check enough target token (if target token is native) has been sent for the trade
        if (_targetToken == NATIVE_TOKEN && msg.value < sourceAmount) {
            revert InsufficientNativeTokenSent();
        }
        _targetToken.safeTransferFrom(msg.sender, address(this), sourceAmount);
        // transfer the tokens to caller
        token.safeTransfer(msg.sender, targetAmount);

        // if no final target token is defined, transfer the target token to `transferAddress`
        if (Token.unwrap(_finalTargetToken) == address(0)) {
            _transferProceeds(_targetToken, sourceAmount);
        }

        // if remaining balance is below the min token sale amount, reset the auction
        if (_amountAvailableForTrading(token) < _minTokenSaleAmounts[token]) {
            _resetTrading(token, 0);
        }

        // if available target token trading amount is below the min target token sale amount, reset the target token auction
        if (
            Token.unwrap(_finalTargetToken) != address(0) &&
            _amountAvailableForTrading(_targetToken) <
            _minTokenSaleAmounts[_targetToken] / _minTokenSaleAmountMultiplier
        ) {
            _resetTradingTarget(0);
        }

        // if the target token is native, refund any excess native token to caller
        if (_targetToken == NATIVE_TOKEN && msg.value > sourceAmount) {
            payable(msg.sender).sendValue(msg.value - sourceAmount);
        }

        return sourceAmount;
    }

    function _sellTargetForFinalTarget(uint128 targetAmount, uint128 maxInput) private returns (uint128) {
        uint128 sourceAmount = expectedTradeInput(_targetToken, targetAmount);
        // revert if trade requires 0 finalTarget tokens
        if (sourceAmount == 0) {
            revert InvalidTrade();
        }
        // revert if trade requires more than maxInput
        if (sourceAmount > maxInput) {
            revert GreaterThanMaxInput();
        }
        // revert if unnecessary native token is received
        if (_finalTargetToken != NATIVE_TOKEN && msg.value > 0) {
            revert UnnecessaryNativeTokenReceived();
        }
        // check enough final target token (if final target token is native) has been sent for the trade
        if (_finalTargetToken == NATIVE_TOKEN && msg.value < sourceAmount) {
            revert InsufficientNativeTokenSent();
        }
        _finalTargetToken.safeTransferFrom(msg.sender, address(this), sourceAmount);
        // transfer the _targetToken to the user
        // safe due to nonReentrant modifier (forwards all available gas if native)
        _targetToken.unsafeTransfer(msg.sender, targetAmount);

        _transferProceeds(_finalTargetToken, sourceAmount);

        // if final target token is native, refund any excess native token to caller
        if (_finalTargetToken == NATIVE_TOKEN && msg.value > sourceAmount) {
            payable(msg.sender).sendValue(msg.value - sourceAmount);
        }

        // update the available target token sale amount
        _targetTokenSaleAmount.current -= targetAmount;

        // check if remaining target token sale amount is below the min target token sale amount
        if (_targetTokenSaleAmount.current < _minTokenSaleAmounts[_targetToken]) {
            // top up the target token sale amount
            _targetTokenSaleAmount.current = Math
                .min(_targetToken.balanceOf(address(this)), _targetTokenSaleAmount.initial)
                .toUint128();
            // reset the price to price * priceResetMultiplier and restart trading
            Price memory price = tokenPrice(_targetToken);
            price.sourceAmount *= _priceResetMultiplier;
            _initialPrice[_targetToken] = price;
            _tradingStartTimes[_targetToken] = uint32(block.timestamp);
            // slow down halflife to `targetTokenPriceDecayHalfLifeOnReset`
            _setTargetTokenPriceDecayHalfLife(_targetTokenPriceDecayHalfLifeOnReset);
            // emit price updated event
            emit PriceUpdated({ token: _targetToken, price: price });
        }

        return sourceAmount;
    }

    /**
     * @dev Set minimum token sale amount multiplier helper
     */
    function _setMinTokenSaleAmountMultiplier(uint32 newMinTokenSaleAmountMultiplier) private {
        uint32 prevMinTokenSaleAmountMultiplier = _minTokenSaleAmountMultiplier;

        // return if the minimum token sale amount multiplier is the same
        if (prevMinTokenSaleAmountMultiplier == newMinTokenSaleAmountMultiplier) {
            return;
        }

        _minTokenSaleAmountMultiplier = newMinTokenSaleAmountMultiplier;

        emit MinTokenSaleAmountMultiplierUpdated({
            prevMinTokenSaleAmountMultiplier: prevMinTokenSaleAmountMultiplier,
            newMinTokenSaleAmountMultiplier: newMinTokenSaleAmountMultiplier
        });
    }

    /**
     * @dev set price reset multiplier helper
     */
    function _setPriceResetMultiplier(uint32 newPriceResetMultiplier) private {
        uint32 prevPriceResetMultiplier = _priceResetMultiplier;

        // return if the price reset multiplier is the same
        if (prevPriceResetMultiplier == newPriceResetMultiplier) {
            return;
        }

        _priceResetMultiplier = newPriceResetMultiplier;

        emit PriceResetMultiplierUpdated({
            prevPriceResetMultiplier: prevPriceResetMultiplier,
            newPriceResetMultiplier: newPriceResetMultiplier
        });
    }

    /**
     * @dev set price decay half-life helper
     */
    function _setPriceDecayHalfLife(uint32 newPriceDecayHalfLife) private {
        uint32 prevPriceDecayHalfLife = _priceDecayHalfLife;

        // return if the price decay half-life is the same
        if (prevPriceDecayHalfLife == newPriceDecayHalfLife) {
            return;
        }

        _priceDecayHalfLife = newPriceDecayHalfLife;

        emit PriceDecayHalfLifeUpdated({
            prevPriceDecayHalfLife: prevPriceDecayHalfLife,
            newPriceDecayHalfLife: newPriceDecayHalfLife
        });
    }

    /**
     * @dev set target token price decay half-life helper
     */
    function _setTargetTokenPriceDecayHalfLife(uint32 newPriceDecayHalfLife) private {
        uint32 prevPriceDecayHalfLife = _targetTokenPriceDecayHalfLife;

        // return if the price decay half-life is the same
        if (prevPriceDecayHalfLife == newPriceDecayHalfLife) {
            return;
        }

        _targetTokenPriceDecayHalfLife = newPriceDecayHalfLife;

        emit TargetTokenPriceDecayHalfLifeUpdated({
            prevPriceDecayHalfLife: prevPriceDecayHalfLife,
            newPriceDecayHalfLife: newPriceDecayHalfLife
        });
    }

    /**
     * @dev set target token price decay half-life on price reset helper
     */
    function _setTargetTokenPriceDecayHalfLifeOnReset(uint32 newPriceDecayHalfLife) private {
        uint32 prevPriceDecayHalfLife = _targetTokenPriceDecayHalfLifeOnReset;

        // Return if the price decay half-life is the same.
        if (prevPriceDecayHalfLife == newPriceDecayHalfLife) {
            return;
        }

        _targetTokenPriceDecayHalfLifeOnReset = newPriceDecayHalfLife;

        emit TargetTokenPriceDecayHalfLifeOnResetUpdated({
            prevPriceDecayHalfLife: prevPriceDecayHalfLife,
            newPriceDecayHalfLife: newPriceDecayHalfLife
        });
    }

    /**
     * @dev set max target token sale amount helper
     */
    function _setMaxTargetTokenSaleAmount(uint128 newTargetTokenSaleAmount) private {
        uint128 prevTargetTokenSaleAmount = _targetTokenSaleAmount.initial;

        // return if the target token sale amount is the same
        if (prevTargetTokenSaleAmount == newTargetTokenSaleAmount) {
            return;
        }

        _targetTokenSaleAmount.initial = newTargetTokenSaleAmount;

        // check if the new max sale amount is below the current available target token sale amount
        if (newTargetTokenSaleAmount < _targetTokenSaleAmount.current) {
            _targetTokenSaleAmount.current = Math
                .min(_targetToken.balanceOf(address(this)), newTargetTokenSaleAmount)
                .toUint128();
        }

        emit MaxTargetTokenSaleAmountUpdated({
            prevTargetTokenSaleAmount: prevTargetTokenSaleAmount,
            newTargetTokenSaleAmount: newTargetTokenSaleAmount
        });
    }

    /**
     * @dev set min token sale amount helper
     */
    function _setMinTokenSaleAmount(Token token, uint128 newMinTokenSaleAmount) private {
        uint128 prevMinTokenSaleAmount = _minTokenSaleAmounts[token];

        // return if the min eth sale amount is the same
        if (prevMinTokenSaleAmount == newMinTokenSaleAmount) {
            return;
        }

        _minTokenSaleAmounts[token] = newMinTokenSaleAmount;

        emit MinTokenSaleAmountUpdated({
            token: token,
            prevMinTokenSaleAmount: prevMinTokenSaleAmount,
            newMinTokenSaleAmount: newMinTokenSaleAmount
        });
    }

    function _setRewardsPPM(uint32 newRewardsPPM) private {
        uint32 prevRewardsPPM = _rewardsPPM;

        // return if the rewards PPM is the same
        if (prevRewardsPPM == newRewardsPPM) {
            return;
        }

        _rewardsPPM = newRewardsPPM;

        emit RewardsUpdated({ prevRewardsPPM: prevRewardsPPM, newRewardsPPM: newRewardsPPM });
    }

    function _setPairDisabled(Token token, bool disabled) private {
        bool prevPairStatus = _disabledPairs[token];

        // return if the pair status is the same
        if (prevPairStatus == disabled) {
            return;
        }

        _disabledPairs[token] = disabled;

        emit PairDisabledStatusUpdated(token, prevPairStatus, disabled);
    }

    function _setTransferAddress(address newTransferAddress) private {
        address prevTransferAddress = _transferAddress;

        // return if the transfer address is the same
        if (prevTransferAddress == newTransferAddress) {
            return;
        }

        _transferAddress = payable(newTransferAddress);

        emit TransferAddressUpdated({
            prevTransferAddress: prevTransferAddress,
            newTransferAddress: newTransferAddress
        });
    }

    /**
     * @dev returns true if the auction price is below or equal to the minimum possible price
     * @dev check if timeElapsed / priceDecayHalfLife >= 128
     */
    function _auctionPriceIsBelowMinimum(Token token) private view returns (bool) {
        // cache trading start time to save gas
        uint32 tradingStartTime = _tradingStartTimes[token];
        // trading hasn't been enabled, return false
        if (tradingStartTime == 0) {
            return false;
        }
        // get time elapsed since trading was enabled
        uint32 timeElapsed = uint32(block.timestamp) - tradingStartTime;
        // get the halflife for the token
        uint32 currentPriceDecayHalfLife = token == _targetToken ? _targetTokenPriceDecayHalfLife : _priceDecayHalfLife;
        // check if the maximum amount of halflifes have been reached
        return timeElapsed / currentPriceDecayHalfLife >= 128;
    }

    /**
     * @dev returns the token amount available for trading
     */
    function _amountAvailableForTrading(Token token) private view returns (uint128) {
        if (token == _targetToken) {
            return _targetTokenSaleAmount.current;
        } else {
            return token.balanceOf(address(this)).toUint128();
        }
    }

    /**
     * @dev validate token helper
     */
    function _validToken(Token token) private view {
        // validate trading is enabled for token
        if (!_tradingEnabled(token)) {
            revert TradingDisabled();
        }
        // validate pair isn't disabled
        if (_disabledPairs[token]) {
            revert PairDisabled();
        }
    }

    function _validateTokens(Token[] calldata tokens) private pure {
        uint256 len = tokens.length;
        if (len == 0) {
            revert InvalidTokenLength();
        }
        for (uint256 i = 0; i < len; i = uncheckedInc(i)) {
            Token token = tokens[i];
            // revert for invalid token address
            if (token == Token.wrap(address(0))) {
                revert InvalidToken();
            }
            // validate token has no duplicates
            for (uint256 j = uncheckedInc(i); j < len; j = uncheckedInc(j)) {
                if (token == tokens[j]) {
                    revert DuplicateToken();
                }
            }
        }
    }

    /**
     * @dev validate token helper
     */
    function _validPrice(Price memory price) private pure {
        if (price.sourceAmount == 0 || price.targetAmount == 0) {
            revert InvalidPrice();
        }
    }

    /**
     * @dev return true if trading is enabled for token
     */
    function _tradingEnabled(Token token) private view returns (bool) {
        return _tradingStartTimes[token] != 0;
    }

    /**
     * @dev allocates the rewards to caller
     */
    function _allocateRewards(address sender, Token[] memory tokens, uint256[] memory rewardAmounts) private {
        uint256 len = tokens.length;
        for (uint256 i = 0; i < len; i = uncheckedInc(i)) {
            Token token = tokens[i];
            uint256 rewardAmount = rewardAmounts[i];
            // transfer the rewards to caller
            // safe due to nonReentrant modifier (forwards all available gas in case of ETH)
            token.unsafeTransfer(sender, rewardAmount);
        }
    }

    /**
     * @dev helper function to reset the auction to the initial price
     */
    function _resetAuction(Token token) private returns (Price memory) {
        Price memory price = Price({
            sourceAmount: INITIAL_PRICE_SOURCE_AMOUNT,
            targetAmount: INITIAL_PRICE_TARGET_AMOUNT
        });
        _tradingStartTimes[token] = uint32(block.timestamp);
        _initialPrice[token] = price;
        return price;
    }

    function _transferProceeds(Token token, uint256 amount) private {
        // increment totalCollected amount
        _totalCollected += amount;

        // if tank address is not 0, proceeds stay in the vortex
        if (_tank != address(0)) {
            // safe due to nonReentrant modifier (forwards all available gas in case of ETH)
            token.unsafeTransfer(_tank, amount / 2);
        }

        // if transfer address is 0, proceeds stay in the vortex
        if (_transferAddress == address(0)) {
            return;
        }
        uint256 halfAmount = amount - (amount / 2);

        // safe due to nonReentrant modifier (forwards all available gas in case of ETH)
        token.unsafeTransfer(_transferAddress, halfAmount);
    }

    function uncheckedInc(uint256 i) private pure returns (uint256 j) {
        unchecked {
            j = i + 1;
        }
    }
}
