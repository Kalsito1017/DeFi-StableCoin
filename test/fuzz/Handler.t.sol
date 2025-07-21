//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {console} from "lib/forge-std/src/console.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    MockV3Aggregator ethUsdPriceFeed;

    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
        ethUsdPriceFeed = MockV3Aggregator(
            dscEngine.getCollateralTokenPriceFeed(address(weth))
        );
    }
    function mintDsc(uint256 amountDsc, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;

        address sender = usersWithCollateralDeposited[
            addressSeed % usersWithCollateralDeposited.length
        ];

        (uint256 totalMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(sender);

        uint256 liquidationThreshold = dscEngine.getLiquidationThreshold(); // e.g. 7500 means 75.00%

        // Note: liquidationThreshold is basis points (e.g. 7500 = 75%), so divide by 10000
        uint256 maxMintable = (collateralValueInUsd * liquidationThreshold) /
            10000;

        if (maxMintable <= totalMinted) return;

        uint256 availableToMint = maxMintable - totalMinted;

        availableToMint = (availableToMint * 999) / 1000; // to avoid rounding issues

        uint256 amount = bound(amountDsc, 1, availableToMint);

        if (amount == 0) return;

        vm.startPrank(sender);
        dscEngine.mintDsc(amount);
        vm.stopPrank();

        timesMintIsCalled++;
    }

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 MAX_SAFE = 1e30; // Adjust this to your app's design
        amountCollateral = bound(amountCollateral, 1e18, MAX_SAFE); // This is correct

        // log to verify:
        console.log(
            "depositCollateral amountCollateral after bound: %s",
            amountCollateral
        );

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(
            address(collateral),
            msg.sender
        );
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
    }
    function updateCollateralPrice(uint96 newPrice) public {
        uint256 MIN_PRICE = 500e8; // $500
        uint256 MAX_PRICE = 5000e8; // $5,000 — tighter than before

        newPrice = uint96(bound(newPrice, MIN_PRICE, MAX_PRICE));
        ethUsdPriceFeed.updateAnswer(int256(uint256(newPrice)));
    }

    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
