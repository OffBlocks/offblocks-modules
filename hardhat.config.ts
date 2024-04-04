import {HardhatUserConfig, vars} from "hardhat/config";
import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-viem";

const ALCHEMY_BASE_SEPOLIA_API_KEY = vars.get("ALCHEMY_BASE_SEPOLIA_API_KEY");
const SEPOLIA_PRIVATE_KEY = vars.get("SEPOLIA_PRIVATE_KEY");
const ETHERSCAN_KEY = vars.get("ETHERSCAN_KEY");
const BASE_ETHERSCAN_KEY = vars.get("BASE_ETHERSCAN_KEY");

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
  },
  networks: {
    sepolia: {
      url: "https://sepolia.drpc.org",
      accounts: [SEPOLIA_PRIVATE_KEY],
    },
    baseSepolia: {
      url:
        "https://base-sepolia.g.alchemy.com/v2/" + ALCHEMY_BASE_SEPOLIA_API_KEY,
      accounts: [SEPOLIA_PRIVATE_KEY],
    },
  },
  ignition: {
    strategyConfig: {
      create2: {
        salt: "0x7101fad7e81cfe5a6fcbfcec05cc7b7c4c1ccf262bb01f1f20b8750826debc47",
      },
    },
  },
  etherscan: {
    apiKey: {
      sepolia: ETHERSCAN_KEY,
      baseSepolia: BASE_ETHERSCAN_KEY,
    },
    customChains: [
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org/",
        },
      },
    ],
  },
  sourcify: {
    enabled: false,
  },
};

export default config;
