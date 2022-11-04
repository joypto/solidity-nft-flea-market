import { HardhatUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-toolbox'
import 'hardhat-abi-exporter'
import 'hardhat-contract-sizer'

const config: HardhatUserConfig = {
    solidity: {
        compilers: [
            {
                version: '0.8.17',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000000
                    }
                }
            }
        ]
    },
    abiExporter: {
        path: './data/abi',
        runOnCompile: true,
        clear: true,
        flat: false,
        spacing: 4
    }
}

export default config
