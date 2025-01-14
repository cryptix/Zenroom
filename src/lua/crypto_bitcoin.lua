--[[
--This file is part of zenroom
--
--Copyright (C) 2021 Dyne.org foundation
--designed, written and maintained by Alberto Lerda
--
--This program is free software: you can redistribute it and/or modify
--it under the terms of the GNU Affero General Public License v3.0
--
--This program is distributed in the hope that it will be useful,
--but WITHOUT ANY WARRANTY; without even the implied warranty of
--MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--GNU Affero General Public License for more details.
--
--Along with this program you should have received a copy of the
--GNU Affero General Public License v3.0
--If not, see http://www.gnu.org/licenses/agpl.txt
--
--]]

local btc = {}

function btc.address_from_public_key(public_key)
   local SHA256 = HASH.new('sha256')
   local RMD160 = HASH.new('ripemd160')
   return RMD160:process(SHA256:process(public_key))

end

function btc.dsha256(msg)
   local SHA256 = HASH.new('sha256')
   return SHA256:process(SHA256:process(msg))
end

function btc.wif_to_sk(wif)
   if not type(wif) == 'zenroom.octet' then
      error("invalid bitcoin key type, not an octet: "..type(wif), 3) end
   local len = #wif
   if not (len == 32+6) then
      error("Invalid bitcoin key, wrong WIF size: "..len.." bytes", 3) end
   local ver = wif:chop(1):hex()
   if not(ver == 'ef' or ver == '80') then
      error("Invalid bitcoin key version: "..ver, 3) end
   local compress = wif:sub(34,34):hex()
   if not(compress == '01') then
      error("Invalid bitcoin key compression byte: "..wif:sub(len, len):hex(), 3) end

   local data = wif:sub(1, len-4)

   local check = btc.dsha256(data):chop(4)

   if not(wif:sub(len-3, len) == check) then
      error("Invalid bitcoin key: checksum mismatch", 3) end

   return wif:sub(2,len-5)
end


-- 0x80 = Mainnet
-- 0xEF = Testnet
function btc.sk_to_wif(sk, vs)
   local ver
   if vs == 'testnet' then
      ver = O.from_hex('EF')
   else
      ver = O.from_hex('80')
   end
   local res = ver..sk
   res = res..O.from_hex('01') -- compressed public key
   res = res..btc.dsha256(res):chop(4) -- checksum
   return res
end

function btc.sk_to_pubc(sk)
   if not #sk == 32 then
      error("Invalid bitcoin key size: "..#sk) end
   return( ECDH.compress_public_key( ECDH.pubgen(sk) ) )

   -- local x, y = ECDH.pubxy(pub)
   -- local pfx = fif( BIG.parity( BIG.new(y) ),
   -- 		    OCTET.from_hex('03'), OCTET.from_hex('02') )
   -- return(pfx .. x)

end
-- variable length encoding for integer based on the
-- actual length of the number
function btc.encode_compact_size(n)
   local res, padding, prefix, le -- littleEndian;

   if type(n) ~= "zenroom.big" then
      n = INT.new(n)
   end
   
   padding = 0
   res = O.new()
   if n <= INT.new(252) then
      res = n:octet()
   else
      le = n:octet():reverse()
      prefix = O.new()
      if n <= INT.new('0xffff') then
	 prefix = O.from_hex('fd') 
	 padding = 2
      elseif n <= INT.new('0xffffffff') then
	 prefix = O.from_hex('fe')
	 padding = 4
      elseif n <= INT.new('0xffffffffffffffff') then
	 prefix = O.from_hex('ff')
	 padding = 8
      else
	 padding = #le
      end
      res = prefix .. le
      padding = padding - #le
   end

   if padding > 0 then
      res = res .. O.zero(padding)
   end

   return res
end

local function decode_compact_size_at_index(raw, i)
   local b1

   b1 = tonumber(raw:sub(i,i):hex(), 16)
   local s, e -- start and end index
   if b1 < 0xfd then
      s, e = 1, 1
   elseif b1 == 0xfd then
      s, e = 2, 3
   elseif b1 == 0xfe then
      s, e = 2, 5
   else
      s, e = 2, 9
   end
   return INT.new(raw:sub(i+s-1, i+e-1)), i+e
end

-- fixed size encoding for integer
function btc.to_uint(num, nbytes)
   if type(num) ~= "zenroom.big" then
      num = INT.new(num)
   end
   num = num:octet():reverse()
   if #num < nbytes then
      num = num .. O.zero(nbytes - #num)
   end
   return num
end

-- read little endian number from transaction raw at position i 
local function read_uint(raw, i, nbytes)
   return tonumber(raw:sub(i,i+nbytes-1):reverse():hex(), 16), i+nbytes
end
-- The sender address is not in the raw transaction
function btc.decode_raw_transaction(raw, sender_address, amounts_spent)
   local SCRIPT_SIZE_LIMIT = BIG.from_decimal('10000')
   local tx
   local i=1
   local scriptBytes
   tx = {}
   -- version (little endian)
   tx.version, i = read_uint(raw, i, 4)
   assert(tx.version == 1 or tx.version == 2)

   -- check if this is segwit, BIP 141

   segwit = (raw:sub(i, i+1) == O.from_hex('0001'))
   if segwit then
      i=i+2
   end
   
   -- read txin
   local n_txin
   n_txin, i = decode_compact_size_at_index(raw, i)
   tx.txIn = {}
   for j=1,tonumber(n_txin:octet():hex(), 16),1 do
      local currIn = {}
      -- previous output
      currIn.txid = raw:sub(i, i+32-1):reverse()
      i=i+32

      currIn.vout, i = read_uint(raw, i, 4)

      currIn.amountSpent = amounts_spent[j]

      scriptBytes, i = decode_compact_size_at_index(raw, i)
      assert(scriptBytes < SCRIPT_SIZE_LIMIT)
      scriptBytes = tonumber(scriptBytes:octet():hex(), 16)
      if scriptBytes > 0 then
	 -- empty script
	 i = i + scriptBytes
      end
      
      currIn.sequence = raw:sub(i, i+3):reverse()
      i = i + 4

      currIn.address = sender_address

      table.insert(tx.txIn, currIn)
   end
   -- read txout
   n_txout, i = decode_compact_size_at_index(raw, i)
   tx.txOut = {}
   for j=1,tonumber(n_txout:octet():hex(), 16),1 do
      local currOut = {}
      currOut.amount = BIG.new(raw:sub(i,i+8-1):reverse())
      i=i+8

      scriptBytes, i = decode_compact_size_at_index(raw, i)
      assert(scriptBytes < SCRIPT_SIZE_LIMIT)
      scriptBytes = tonumber(scriptBytes:octet():hex(), 16)
      if scriptBytes > 0 then
	 -- decode the script
	 -- the script is 00 ADDRESS_LEN ADDRESS
	 -- test segwit ver 0 script
	 assert(raw:sub(i,i) == O.from_hex('00'))
	 local addressLen = tonumber(raw:sub(i+1,i+1):hex(), 16)

	 assert(2+addressLen == scriptBytes)

	 currOut.address = raw:sub(i+2, i+scriptBytes-1)

	 i = i + scriptBytes
      end

      table.insert(tx.txOut, currOut)
   end

   -- read witness (if segwit)
   if segwit then
      tx.witness = {}
      for j=1,#tx.txIn,1 do
      	 stackSize, i = decode_compact_size_at_index(raw, i)
      	 stackSize = tonumber(stackSize:octet():hex(), 16)
      	 items = {}
      	 for k=1,stackSize,1 do
      	    itemBytes, i = decode_compact_size_at_index(raw, i)
      	    itemBytes = tonumber(itemBytes:octet():hex(), 16)
	    item = raw:sub(i, i+itemBytes-1)
	    i=i+itemBytes
      	    table.insert(items, item)
      	 end
      	 table.insert(tx.witness, items)
      end
   end

   -- read nlocktime
   tx.nLockTime, i = read_uint(raw, i, 4)

   return tx
end

-- with not coinbase input
function btc.build_raw_transaction(tx)
   local raw, script
   raw = O.new()

   sigwit = (tx["witness"] and #tx["witness"]>0)

   -- version
   raw = raw .. O.from_hex('02000000')


   if sigwit then
      -- marker + flags
      raw = raw .. O.from_hex('0001')
   end
   
   raw = raw .. btc.encode_compact_size(INT.new(#tx.txIn))

   -- txIn
   for _, v in pairs(tx.txIn) do
      -- outpoint (hash and index of the transaction)
      raw = raw .. v.txid:reverse() .. btc.to_uint(v.vout, 4)
      -- the script depends on the signature
      script = O.new()

      raw = raw .. btc.encode_compact_size(#script) .. script
      
      -- Sequence number disabled
      raw = raw .. O.from_hex('ffffffff')
   end

   raw = raw .. btc.encode_compact_size(INT.new(#tx.txOut))

   -- txOut
   for _, v in pairs(tx.txOut) do
      --raw = raw .. btc.to_uint(v.amount, 8)
      local amount = O.new(v.amount)
      raw = raw .. amount:reverse()
      if #v.amount < 8 then
	 raw = raw .. O.zero(8 - #amount)
      end
      -- fixed script to send bitcoins
      -- OP_DUP OP_HASH160 20byte
      --script = O.from_hex('76a914')

      --script = script .. v.address

      -- OP_EQUALVERIFY OP_CHECKSIG
      --script = script .. O.from_hex('88ac')
      -- Bech32
      script = O.from_hex('0014')
      script = script .. v.address -- readBech32Address(v.address)
      
      raw = raw .. btc.encode_compact_size(#script) .. script
   end

   if sigwit then
      -- Documentation https://bitcoincore.org/en/segwit_wallet_dev/
      -- The documentation talks about "stack items" but it doesn't specify
      -- which are they, I think that It depends on the type of transaction
      -- (P2SH or P2PKH)

      -- The size of witnesses is not necessary because it is equal to the number of
      -- txin
      --raw = raw .. btc.encode_compact_size(#tx["witness"])

      for _, v in pairs(tx["witness"]) do
	 -- encode all the stack items for the witness
	 raw = raw .. btc.encode_compact_size(#v)
	 for _, s in pairs(v) do
	    raw = raw .. btc.encode_compact_size(#s)
	    raw = raw .. s
	 end
      end
   end

   raw = raw .. O.from_hex('00000000')
   
   return raw
end

local function encode_with_prepend(bytes)
   if tonumber(bytes:sub(1,1):hex(), 16) >= 0x80 then
      bytes = O.from_hex('00') .. bytes
   end

   return bytes
end

function btc.encode_der_signature(sig)
   local res, tmp;

   res = O.new()

   -- r
   tmp = encode_with_prepend(sig.r)
   res = res .. O.from_hex('02') .. INT.new(#tmp):octet() .. tmp

   -- s
   tmp = encode_with_prepend(sig.s)
   res = res .. O.from_hex('02') .. INT.new(#tmp):octet() .. tmp
   
   res = O.from_hex('30') .. INT.new(#res):octet() .. res
   return res
end

local function read_number_from_der(raw, pos)
   local size
   assert(raw:sub(pos, pos) == O.from_hex('02'))
   pos= pos+1
   size = tonumber(raw:sub(pos, pos):hex(), 16)
   pos = pos +1

   -- If the first byte is a 0 do not consider it
   if raw:sub(pos, pos) == O.from_hex('00') then
      pos = pos +1
      size = size -1
   end

   data = raw:sub(pos, pos+size-1)

   return {
      data,
      pos+size
   }
   
   
end

function btc.decode_der_signature(raw)
   local sig, tmp, size;
   sig = {}

   assert(raw:chop(1) == O.from_hex('30'))

   size = tonumber(raw:sub(2,2):hex(), 16)

   tmp = read_number_from_der(raw, 3)

   sig.r = tmp[1]
   tmp = tmp[2]

   tmp = read_number_from_der(raw, tmp)

   sig.s = tmp[1]

   return sig
end

function btc.hash_prevouts(tx)
   local raw
   local H
   H = HASH.new('sha256')

   raw = O.new()

   for _, v in pairs(tx.txIn) do
      raw = raw .. v.txid:reverse() .. btc.to_uint(v.vout, 4)
   end

   return H:process(H:process(raw))
end

function btc.hash_sequence(tx)
   local raw
   local H
   local seq
   H = HASH.new('sha256')

   raw = O.new()

   for _, v in pairs(tx.txIn) do
      seq = v['sequence']
      if not seq then
	 -- default value, not enabled
	 seq = O.from_hex('ffffffff')
      end
      raw = raw .. btc.to_uint(seq, 4)
   end
   
   return H:process(H:process(raw))
end

function btc.hash_outputs(tx)
   local raw
   local H
   local seq
   H = HASH.new('sha256')

   raw = O.new()

   for _, v in pairs(tx.txOut) do
      amount = O.new(v.amount)
      raw = raw .. amount:reverse()
      if #v.amount < 8 then
	 raw = raw .. O.zero(8 - #amount)
      end
      -- This is specific to Bech32 addresses, we should be able to verify the kind of address
      raw = raw .. O.from_hex('160014') .. v.address

   end

   return H:process(H:process(raw))
end


-- BIP0143
-- Double SHA256 of the serialization of:
--      1. nVersion of the transaction (4-byte little endian)
--      2. hash_prevouts (32-byte hash)
--      3. hash_sequence (32-byte hash)
--      4. outpoint (32-byte hash + 4-byte little endian) 
--      5. scriptCode of the input (serialized as scripts inside CTxOuts)
--      6. value of the output spent by this input (8-byte little endian)
--      7. nSequence of the input (4-byte little endian)
--      8. hash_outputs (32-byte hash)
--      9. nLocktime of the transaction (4-byte little endian)
--     10. sighash type of the signature (4-byte little endian)
function btc.build_transaction_to_sign(tx, i)
   local raw
   local amount
   raw = O.new()
   --      1. nVersion of the transaction (4-byte little endian)
   raw = raw .. btc.to_uint(tx.version, 4)
   --      2. hash_prevouts (32-byte hash)
   raw = raw .. btc.hash_prevouts(tx)
   --      3. hash_sequence (32-byte hash)
   raw = raw .. btc.hash_sequence(tx)
   --      4. outpoint (32-byte hash + 4-byte little endian)
   raw = raw .. tx.txIn[i].txid:reverse() .. btc.to_uint(tx.txIn[i].vout, 4)
   --      5. scriptCode of the input (serialized as scripts inside CTxOuts)
   raw = raw .. O.from_hex('1976a914') .. tx.txIn[i].address  .. O.from_hex('88ac')
   --      6. value of the output spent by this input (8-byte little endian)
   amount = O.new(tx.txIn[i].amountSpent)
   raw = raw .. amount:reverse()
   if #amount < 8 then
      raw = raw .. O.zero(8 - #amount)
   end
   --      7. nSequence of the input (4-byte little endian)
   raw = raw .. tx.txIn[i].sequence:reverse()
   --      8. hash_outputs (32-byte hash)
   raw = raw .. btc.hash_outputs(tx)
   --      9. nLocktime of the transaction (4-byte little endian)
   raw = raw .. btc.to_uint(tx.nLockTime, 4)
   --     10. sighash type of the signature (4-byte little endian)
   raw = raw .. btc.to_uint(tx.nHashType, 4)

   return raw
end

-- Here I sign the transaction
function btc.build_witness(tx, sk)
   local pk = ECDH.compress_public_key(ECDH.pubgen(sk))
   local witness = {}
   for i=1,#tx.txIn,1 do
      if tx.txIn[i].sigwit then
	 local rawTx = btc.build_transaction_to_sign(tx, i)
	 local sigHash = btc.dsha256(rawTx)
	 local sig = ECDH.sign_ecdh(sk, sigHash)
	 witness[i] = {
	    btc.encode_der_signature(sig) .. O.from_hex('01'),
	    pk
	 }
      else
	 witness[i] = O.zero(1)
      end
   end

   return witness
end

function btc.verify_witness(tx)
   tx.nHashType = O.from_hex('00000001')
   if tx.witness == nil then
      return false
   end
   for i, v in pairs(tx.witness) do
      local rawTx = btc.build_transaction_to_sign(tx, i)
      local sigHash = btc.dsha256(rawTx)
      local sig = btc.decode_der_signature(v[1])
      if not ECDH.verify_hashed(ECDH.uncompress_public_key(v[2]), sigHash, sig, #sigHash) then
	 return false
      end
   end
   return true
end

-- -- Pay attention to the amount it has to be multiplied for 10^8

-- unspent: list of unspent transactions
-- to: receiver bitcoin address (must be segwit/Bech32!)
-- amount: satoshi to transfer (BIG integer)

-- return nil if it cannot build the transaction
-- (for example if there are not enough founds)
function btc.build_tx_from_unspent(unspent, to, amount, fee)
   local tx, i, currentAmount
   tx = {
      version=2,
      txIn = {},
      txOut = {},
      nLockTime=0,
      nHashType=O.from_hex('00000001')
   }


   i=1
   currentAmount = INT.new(0)
   while i <= #unspent and currentAmount < amount+fee do
      currentAmount = currentAmount + unspent[i].amount
      tx.txIn[i] = {
	 txid = unspent[i].txid,
	 vout = unspent[i].vout,
	 sigwit = O.from_hex('01'), -- this should be true
	 address = unspent[i].address,
	 amountSpent = unspent[i].amount,
	 sequence = O.from_hex('ffffffff'),
	 --scriptPubKey = unspent[i].scriptPubKey
      }
      i=i+1
   end
   if currentAmount < amount+fee or i==1 then
      -- Not enough BTC
      return nil
   end

   -- Add exactly two outputs, one for the receiver and one for the exceding amount
   tx.txOut[1] = {
      amount = amount,
      address = to
   }

   if currentAmount > amount+fee then
      tx.txOut[2] = {
	 amount = currentAmount-amount-fee,
	 address = tx.txIn[1].address
      }
   end

   return tx
end

function btc.value_btc_to_satoshi(value)
   pos = value:find("%.")
   decimals = value:sub(pos+1, #value)

   if #decimals > 8 then
      error("Satoshi is the smallest unit of measure")
   end

   decimals = decimals .. string.rep("0", 8-#decimals)

   return BIG.from_decimal(value:sub(1, pos-1) .. decimals)
end

-- function rawTransactionFromJSON(data, sk)
--    local obj = JSON.decode(data)
--    local sk = btc.read_wif_private_key(sk)

--    for k, v in pairs(obj.unspent) do
--       v.txid = O.from_hex(v.txid)
--       v.amount = valueSatoshiToBTC(v.amount)
--    end

--    local tx = btc.build_tx_from_unspent(obj.unspent, sk, obj.to, btc.big_from_string(obj.amount), btc.big_from_string(obj.fee))

--    tx.witness = btc.build_witness(tx, sk)

--    local rawTx = btc.build_raw_transaction(tx)

--    return rawTx
-- end


return btc
