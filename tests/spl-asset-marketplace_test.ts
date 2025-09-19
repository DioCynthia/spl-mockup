import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
  name: "Ensure creators can create digital asset listings",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const block = chain.mineBlock([
      Tx.contractCall('spl-asset-marketplace', 'create-digital-listing', [
        types.ascii('Design Template'),
        types.utf8('Professional UI/UX design kit'),
        types.uint(1000000),
        types.ascii('design-templates'),
        types.utf8('https://preview.example.com'),
        types.utf8('https://full-asset.example.com'),
        types.uint(10)
      ], deployer.address)
    ]);

    // Assert the transaction was successful
    assertEquals(block.receipts.length, 1);
    assertEquals(block.receipts[0].result.type, 'ok');
  }
});

Clarinet.test({
  name: "Prevent listing creation with invalid parameters",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const block = chain.mineBlock([
      Tx.contractCall('spl-asset-marketplace', 'create-digital-listing', [
        types.ascii('Design Template'),
        types.utf8('Professional UI/UX design kit'),
        types.uint(0), // Invalid price
        types.ascii('design-templates'),
        types.utf8('https://preview.example.com'),
        types.utf8('https://full-asset.example.com'),
        types.uint(20) // Invalid royalty rate
      ], deployer.address)
    ]);

    // Assert the transaction was rejected
    assertEquals(block.receipts.length, 1);
    assertEquals(block.receipts[0].result.type, 'err');
  }
});

Clarinet.test({
  name: "Purchase a digital asset successfully",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const buyer = accounts.get('wallet_1')!;

    // First, create a listing
    const createBlock = chain.mineBlock([
      Tx.contractCall('spl-asset-marketplace', 'create-digital-listing', [
        types.ascii('Design Template'),
        types.utf8('Professional UI/UX design kit'),
        types.uint(1000000),
        types.ascii('design-templates'),
        types.utf8('https://preview.example.com'),
        types.utf8('https://full-asset.example.com'),
        types.uint(10)
      ], deployer.address)
    ]);

    // Then attempt to purchase
    const purchaseBlock = chain.mineBlock([
      Tx.contractCall('spl-asset-marketplace', 'purchase-digital-asset', [
        types.uint(1)
      ], buyer.address)
    ]);

    assertEquals(purchaseBlock.receipts.length, 1);
    assertEquals(purchaseBlock.receipts[0].result.type, 'ok');
  }
});