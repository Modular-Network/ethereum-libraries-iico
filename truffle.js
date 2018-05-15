// Allows us to use ES6 in our migrations and tests.
require('babel-register')
require('babel-polyfill')

module.exports = {
  networks: {
    coverage: {
      host: 'localhost',
      port: 8555,
      network_id: '*',
      gas: 0xfffffffffff,
      gasPrice: 0x01
    },
    development: {
      host: 'localhost',
      port: 8555,
      network_id: '*' // Match any network id
    },
    live: {
      host: 'localhost',
      port: 8545,
      network_id: '1',
      from: '0x475ded3e48d0182fd684e3f78a1ee17659482c3b',
      gas: 6000000,
      gasPrice: 5000000000
    }
  }
}
