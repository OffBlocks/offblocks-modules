import {HardhatUserConfig, vars} from "hardhat/config";
import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox";

const ALCHEMY_BASE_SEPOLIA_API_KEY = vars.get("ALCHEMY_BASE_SEPOLIA_API_KEY");
const SEPOLIA_PRIVATE_KEY = vars.get("SEPOLIA_PRIVATE_KEY");
const ETHERSCAN_KEY = vars.get("ETHERSCAN_KEY");
const BASE_ETHERSCAN_KEY = vars.get("BASE_ETHERSCAN_KEY");

const config: HardhatUserConfig = {
  solidity: "0.8.25",
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
        salt: "0x31087fb5f52dd6901b8d3f2de463ce9da41334b91408a0bc6153304fb1529010",
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
