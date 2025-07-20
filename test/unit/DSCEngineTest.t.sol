// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test} from "lib/forge-std/src/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    DeployDSC public deployer;
    HelperConfig public helperConfig;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether; // 10 ETH
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether; // 10 ETH
    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, , weth, , ) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }
    //Constructor tests
    address[] public tokenAddresses;
    address[] public priceFeedsAddresses;
    function testRevertsIfTokenLengthDoesMatchPriceFeed() public {
        tokenAddresses.push(weth);
        priceFeedsAddresses.push(ethUsdPriceFeed);
        priceFeedsAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAdddressesAndPriceFeedAddressesMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedsAddresses, address(dsc));
    }
    //Price tests
    function testGetUSDValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18l
        uint256 expectedUSDValue = 30_000e18;
        uint256 actualUSDValue = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUSDValue, actualUSDValue, "USD value mismatch");
    }
    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether; // Example USD amount
        uint256 expectedWeth = 0.05 ether; // Example expected WETH amount
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth, "WETH amount mismatch");
    }
    //Collateral tests
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }
    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            AMOUNT_COLLATERAL
        );
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }
    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }
    function testCanDepositCollateral() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUSD) = dscEngine
            .getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(
            weth,
            collateralValueInUSD
        );
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testRedeemCollateralAfterBurn() public depositedCollateral {
        vm.startPrank(USER);

        uint256 mintAmount = 3 ether;
        dscEngine.mintDsc(mintAmount);

        // Approve DSC tokens before burn
        dsc.approve(address(dscEngine), mintAmount);
        dscEngine.burnDsc(mintAmount);

        // Check collateral before redeem
        (, uint256 collateralBefore) = dscEngine.getAccountInformation(USER);

        uint256 redeemAmount = 1 ether;
        dscEngine.redeemCollateral(weth, redeemAmount);

        // Check collateral after redeem
        (, uint256 collateralAfter) = dscEngine.getAccountInformation(USER);

        vm.stopPrank();

        // Assert collateral reduced after redeem
        assert(collateralAfter < collateralBefore);
    }
}
