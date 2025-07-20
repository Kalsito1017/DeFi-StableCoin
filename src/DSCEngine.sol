//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "lib/node_modules/@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "lib/node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
/* @title: Decentralized Stable Coin Engine
 * - 1 token = 1 USD
 * - Exogenous Collateral:
 * - Dollar Pegged
 * - Algorithmically Stable
 * - Backed by wBTC and wETH
 */
contract DSCEngine is ReentrancyGuard {
    // Errors
    error DSCEngine__NeedsBeMoreThanZero();
    error DSCEngine__TokenAdddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOK();
    // State Variables
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% (50% of collateral value)
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //10% bonus for liquidators

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    DecentralizedStableCoin private immutable i_dsc;
    address[] private s_collateralTokens;
    // Events
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 indexed amount
    );
    // Modifiers
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__NeedsBeMoreThanZero();
        }
        _;
    }
    modifier isAllowedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }
    // Constructor
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAdddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }
    // Functions
    /*
     * @notice: Follows CEI pattern to deposit collateral and mint DSC
     * @param tokenCollateralAddress: Address of the collateral token (wETH or wBTC)
     * @param amountCollateral: Amount of collateral to deposit
     * @param amountDscToMint: Amount of DSC to mint
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }
    /*
     * @notice: Follows CEI pattern to deposit collateral
     * @param tokenCollateralAddress: Address of the collateral token (wETH or wBTC)
     * @param amountCollateral: Amount of collateral to deposit
     * @param amountDscToMint: Amount of DSC to mint
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }
    /*
     * @notice: Follows CEI pattern to redeem collateral for DSC
     * @param totalCollateralAddress: Address of the collateral token (wETH or wBTC)
     * @param amountCollateral: Amount of collateral to redeem
     * @param amountDscToBurn: Amount of DSC to burn
     * This function will check the health factor before redeeming collateral
     */
    function redeemCollateralForDsc(
        address totalCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) public {
        _redeemCollateral(
            msg.sender,
            msg.sender,
            totalCollateralAddress,
            amountCollateral
        ); // Redeem the collateral for the user
        _revertIfHealthFactorIsBroken(msg.sender); // Check if the health factor is broken after redeeming collateral
    }
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] -= amountCollateral; // Decrease the amount of collateral deposited by the user
        emit CollateralRedeemed(
            msg.sender,
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            msg.sender,
            amountCollateral
        ); // Transfer the collateral back to the user
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender); // Check if the health factor is broken after redeeming collateral
    }
    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint; // Increase the amount of DSC minted by the user
        _revertIfHealthFactorIsBroken(msg.sender); // Check if the health factor is broken
        bool minted = i_dsc.mint(msg.sender, amountDscToMint); // Transfer the DSC to the user
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        s_DSCMinted[msg.sender] -= amount; // Decrease the amount of DSC minted by the user
        bool success = i_dsc.transferFrom(msg.sender, address(this), amount); // Burn the DSC from the user
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount); // Burn the DSC from the contract
    }
    // Liquidation
    /*
     * @notice: Follows CEI pattern to liquidate a user's collateral
     * @param collateral: Address of the collateral token (wETH or wBTC)
     * @param user: Address of the user to liquidate
     * @param debtToCover: Amount of debt to cover
     * This function will check the health factor before liquidating the user's collateral
     */
    //Follows CEI pattern to liquidate a user's collateral
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK(); // User's health factor is OK, no need to liquidate
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / PRECISION; // 10% bonus for liquidators
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral; // Total collateral to redeem from the user
        _redeemCollateral(
            user,
            msg.sender,
            collateral,
            totalCollateralToRedeem
        ); // Redeem the collateral from the user and transfer it to the liquidator
    }
    function getHealthFactor() external {}
    function _redeemCollateral(
        address tokencollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        s_collateralDeposited[from][tokencollateralAddress] -= amountCollateral; // Decrease the amount of collateral deposited by the user
        emit CollateralRedeemed(
            from,
            to,
            tokencollateralAddress,
            amountCollateral
        );
        bool success = IERC20(collateral).transfer(to, amountCollateral); // Transfer the collateral back to the user
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }
    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
        return (totalDscMinted, collateralValueInUSD);
    }
    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION; // 1000ETH * 50% = 500ETH
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted; // 500ETH * 1e18 / 1000DSC = 500e18
    }
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userhealthFactor = _healthFactor(user);
        if (userhealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userhealthFactor);
        }
    }
    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i]; // Get the token address from the collateral tokens array
            uint256 amount = s_collateralDeposited[user][token]; // Get the amount of collateral deposited by the user for that token
            totalCollateralValueInUsd += getUsdValue(token, amount); // Get the USD value of the collateral deposited by the user for that token
        }
        return totalCollateralValueInUsd;
    }
    function getUsdValue(
        address token,
        uint256 amount
    ) public view isAllowedToken(token) returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
