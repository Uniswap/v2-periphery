#!/usr/bin/env node

const replace = require('replace-in-file')

const TEST_FACTORY_ADDRESS = 'dCCc660F92826649754E357b11bd41C31C0609B9';
const PROD_FACTORY_ADDRESS = 'e2f197885abe8ec7c866cFf76605FD06d4576218';

const TEST_ROUTER_ADDRESS = '84e924C5E04438D2c1Df1A981f7E7104952e6de1';
const PROD_ROUTER_ADDRESS = 'cDbE04934d89e97a24BCc07c3562DC8CF17d8167';

function caseSensitiveReplacer(replacementText) {
  return match => {
    if (match.toLowerCase() === match) {
      return replacementText.toLowerCase();
    } else if (match.toUpperCase() === match) {
      return replacementText.toUpperCase();
    } else {
      return replacementText;
    }
  }
}

console.log('Replacing test contract addresses')
console.log(replace.sync({
  files: [
    "build/*.json"
  ],
  from: [new RegExp(TEST_FACTORY_ADDRESS, 'gi'), new RegExp(TEST_ROUTER_ADDRESS, 'gi')],
  to: [caseSensitiveReplacer(PROD_FACTORY_ADDRESS), caseSensitiveReplacer(PROD_ROUTER_ADDRESS)],
  // countMatches: true,
}));