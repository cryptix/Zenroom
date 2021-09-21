-- Some test with BTC

local BTC = require('crypto_bitcoin')

assert(BTC.read_base58check('cRg4MM15LCfvt4oCddAfUgWm54hXw1LFmkHqs6pwym9QopG5Evpt') == O.from_hex('ef7a1afbb80174a41ad288053b246c7f528f5e746332f95f19e360c95bfb1d03bd01'))

assert(BTC.read_wif_private_key('cRg4MM15LCfvt4oCddAfUgWm54hXw1LFmkHqs6pwym9QopG5Evpt') == O.from_hex('7a1afbb80174a41ad288053b246c7f528f5e746332f95f19e360c95bfb1d03bd'))

assert(BTC.encode_compact_size(INT.new(1)) == O.from_hex('01'))
assert(BTC.encode_compact_size(INT.new(253)) == O.from_hex('fdfd00'))
assert(BTC.encode_compact_size(INT.new(515)) == O.from_hex('fd0302'))

-- Test for encoding and decoding DER signature
sig = {
   r=O.from_hex('ff09e17b84f6a7d30c80bfa610b5b4542f32a8a0d5447a12fb1366d7f01cc44a'),
   s=O.from_hex('573a954c4518331561406f90300e8f3358f51928d43c212a8caed02de67eebee')
}
encodedDER = BTC.encode_der_signature(sig)
newSig = BTC.decode_der_signature(encodedDER)
assert(sig.r == newSig.r and sig.s == newSig.s)
--------------------------
--   test from BIP0143  --
--------------------------
pk = O.from_hex('045476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee6357fd57dee6b46a6b010a3e4a70961ecf44a40e18b279ec9e9fba9c1dbc64896198')
tx = {
   version=1,
   txIn = {
      {
	 txid= O.from_hex("9f96ade4b41d5433f4eda31e1738ec2b36f6e7d1420d94a6af99801a88f7f7ff"),
	 vout= 0,
	 sequence = O.from_hex('ffffffee')
      },
      {
	 txid= O.from_hex("8ac60eb9575db5b2d987e29f301b5b819ea83a5c6579d282d189cc04b8e151ef"),
	 vout= 1,
	 sigwit = true,
	 address = O.from_hex('1d0f172a0ecb48aee1be1f2687d2963ae33f71a1'),
	 amountSpent = O.from_hex('23c34600'),
	 sequence = O.from_hex('ffffffff')
      }
   },
   txOut = {
      {
	 amount = O.from_hex('06b22c20'), -- this maybe should be a number
	 address = O.from_hex('1976a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac') -- I pass directly the script
      },
      {
	 amount = O.from_hex('0d519390'), -- this maybe should be a number
	 address = O.from_hex('1976a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac') -- I pass directly the script
      }
   },
   nLockTime=17,
   nHashType=O.from_hex('00000001'),
}

-- -- This test doesn't work because an input is not segwit
-- assert(BTC.hash_prevouts(tx) == O.from_hex('96b827c8483d4e9b96712b6713a7b68d6e8003a781feba36c31143470b4efd37'))
-- assert(BTC.hash_sequence(tx) == O.from_hex('52b0a642eea2fb7ae638c36f6252b6750293dbe574a806984b8e4d8548339a3b'))
-- assert(BTC.hash_outputs(tx) == O.from_hex('863ef3e1a92afbfdb97f31ad0fc7683ee943e9abcf2501590ff8f6551f47e5e5'))

-- rawTx = BTC.build_transaction_to_sign(tx, 2)
-- print(rawTx:hex())
-- sigHash = BTC.dsha256(rawTx)
-- assert(rawTx == O.from_hex('0100000096b827c8483d4e9b96712b6713a7b68d6e8003a781feba36c31143470b4efd3752b0a642eea2fb7ae638c36f6252b6750293dbe574a806984b8e4d8548339a3bef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a010000001976a9141d0f172a0ecb48aee1be1f2687d2963ae33f71a188ac0046c32300000000ffffffff863ef3e1a92afbfdb97f31ad0fc7683ee943e9abcf2501590ff8f6551f47e5e51100000001000000'))
-- assert(sigHash == O.from_hex('c37af31116d1b27caf68aae9e3ac82f1477929014d5b917657d0eb49478cb670'))
-- sig = {
--    r=O.from_hex('3609e17b84f6a7d30c80bfa610b5b4542f32a8a0d5447a12fb1366d7f01cc44a'),
--    s=O.from_hex('573a954c4518331561406f90300e8f3358f51928d43c212a8caed02de67eebee')
-- }

-- assert(compressPublicKey(pk) == O.from_hex('025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee6357'))
-- assert(ECDH.verify_hashed(pk, sigHash, sig, #sigHash))

----------------------------------------
-- Validate witness from bitcoin core --
----------------------------------------
sk = BTC.read_wif_private_key('cPW7XRee1yx6sujBWeyZiyg18vhhQk9JaxxPdvwGwYX175YCF48G')
pk = ECDH.pubgen(sk)
tx = {
   version=2,
   txIn = {
      {
	 txid= O.from_hex("8cf73380cd054b6936360401b53a9db0cb30e33a7997bfd65fad939579096678"),
	 vout= 0,
	 sigwit = true,
	 address = BTC.read_bech32_address("tb1q04c9a079f3urc5nav647frx4x25hlv5vanfgug"),
	 amountSpent = BIG.from_decimal('1896500'), -- O.from_hex('1cf034'),
	 sequence = O.from_hex('ffffffff')
      }
   },
   txOut = {
      {
	 amount = BIG.from_decimal('1896000'), -- O.from_hex('1cee40'),
	 address = BTC.read_bech32_address('tb1q73czlxl7us4s6num5sjlnq6r0yuf8uh5clr2tm')
      }
   },
   nLockTime=0,
   nHashType=O.from_hex('00000001')
}
assert(BTC.build_raw_transaction(tx) == O.from_hex('0200000001786609799593ad5fd6bf97793ae330cbb09d3ab501043636694b05cd8033f78c0000000000ffffffff0140ee1c0000000000160014f4702f9bfee42b0d4f9ba425f98343793893f2f400000000'))

rawTx = BTC.build_transaction_to_sign(tx, 1)
sigHash = BTC.dsha256(rawTx)

sig = {
   r=O.from_hex('5f5cf053cfd97c8c3c30c31f11d5be369e0f551173d6699db1635f27d5f26a04'),
   s=O.from_hex('7f9d02edd76708ee4b7551d6c25a533b3d346378c843b13c5e992fabf8db018e')
}
assert(BTC.compress_public_key(pk) == O.from_hex('03fe7380f1549462e6f9fff99c2bd0084a2ce568f79f0001f020b4135385394276'))
assert(ECDH.verify_hashed(pk, sigHash, sig, #sigHash))
