# DeFi-StableCoin

## Table of Contents

- [About](#about)
- [Features](#features)
- [Libraries Used](#libraries-used)

## About

DeFi-StableCoin is a decentralized stablecoin protocol built on blockchain technology. It leverages smart contracts to maintain a stable value peg, typically to a fiat currency like the US Dollar, through algorithmic mechanisms or collateral backing.

The core components include:

- **Smart Contracts:** Autonomous contracts deployed on an Ethereum-compatible blockchain that manage the issuance, redemption, and stabilization of the stablecoin without intermediaries.
- **Collateral Management:** Mechanisms to lock collateral assets (e.g., ETH, other tokens) that back the stablecoin, ensuring its value stability and solvency.
- **Price Oracles:** External data feeds integrated into the smart contracts to provide real-time price information essential for maintaining the peg.
- **Governance:** Decentralized protocols that allow stakeholders to propose and vote on system parameters and upgrades.
- **Decentralized Finance (DeFi) Integration:** Compatibility with existing DeFi platforms enabling lending, borrowing, and liquidity provision with the stablecoin.

This architecture ensures transparency, censorship resistance, and reduces reliance on centralized authorities while providing users with a reliable, programmable, and trustless stable digital asset.

## Features

- Stablecoin backed by decentralized mechanisms
- Smart contract integration
- Secure and transparent transactions
- Compatible with Ethereum-based wallets

## Libraries Used

- **forge-std:** A standard library for Foundry that provides utilities for testing, fuzzing, invariant testing, and debugging Solidity smart contracts. It helps build robust, well-tested contracts by offering easy-to-use testing frameworks and cheat codes.

- **OpenZeppelin Contracts:** A widely-used library of secure and community-vetted smart contract components, including ERC20 token standards, access control, and other reusable contract modules. This project uses OpenZeppelin for standard token interfaces and security best practices.

- **Chainlink Brownie:** Chainlink's integration with the Brownie Python framework for smart contract development, testing, and deployment. It includes mocks and interfaces for interacting with Chainlink oracles, enabling secure and reliable price feeds used in the stablecoin protocol.

- **OracleLib (Custom Library):** A Solidity library created to safely handle price feed updates using Chainlink oracles. It verifies the freshness of price data by checking the timestamp against a timeout threshold (3 hours), preventing the use of stale prices in the Decentralized Stable Coin system.

