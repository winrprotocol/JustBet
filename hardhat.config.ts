import { config } from "dotenv";

config({
  path: '.env'
})

import { HardhatUserConfig } from "hardhat/types";

import 'hardhat-abi-exporter';
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
import "@typechain/hardhat";
import "solidity-coverage";
import "hardhat-gas-reporter";

const ACCOUNT_PRIVATE_KEY = process.env.ACCOUNT_PRIVATE_KEY || "";
const ARBSCAN_API_KEY = process.env.ARBSCAN_API_KEY || "";
const ARB_GOERLI_API_KEY = process.env.ARB_GOERLI_API_KEY || "";

const hardhatConfig: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  solidity: {
    compilers: [
      {
        version: "0.8.17",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }
    ]
  },
  networks: {
    hardhat: {},
    arbitrumTestnet: {
      url: `https://arb-goerli.g.alchemy.com/v2/${ARB_GOERLI_API_KEY}`,
      gasPrice: 1000000000,
      accounts: [ACCOUNT_PRIVATE_KEY],
    },
    coverage: {
      url: "http://127.0.0.1:8555", // Coverage launches its own ganache-cli client
    },
  },
  etherscan: {
    apiKey: {
      // For all arbi networks
      arbitrumTestnet: ARBSCAN_API_KEY,
    }
  },
  gasReporter: {
    currency: 'USDT',
    coinmarketcap: process.env.COINMARKETCAP_API,
  },
};

export default hardhatConfig;