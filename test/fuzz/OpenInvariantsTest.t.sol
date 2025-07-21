//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "lib/forge-std/src/Test.sol";
import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    HelperConfig config;
    DecentralizedStableCoin dsc;
    address weth;
    address wbtc;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();
        targetContract(address(dscEngine));
    }
    function invariant_protocolMustHaveMoreValueThanSuply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWthDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));
        uint256 wethValue = dscEngine.getUsdValue(weth, totalWthDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalBtcDeposited);
        assert(wethValue + wbtcValue >= totalSupply);
    }
}
