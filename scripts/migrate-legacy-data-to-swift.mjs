#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const OUTPUT_DIR_NAME = 'fund-pulse';
const LEGACY_STORE_DIR_NAMES = ['Fishing Funds', 'fund-pulse'];
const ENCRYPTION_KEYS = ['fishing-funds', 'fund-pulse'];
const appDataDir = path.join(process.env.HOME, 'Library', 'Application Support', OUTPUT_DIR_NAME);
const outputPath = path.join(appDataDir, 'portfolio.json');
const MARKET_CLOSED_RANGES = [
  ['2026-01-01', '2026-01-03'],
  ['2026-02-15', '2026-02-23'],
  ['2026-04-04', '2026-04-06'],
  ['2026-05-01', '2026-05-05'],
  ['2026-06-19', '2026-06-21'],
  ['2026-09-25', '2026-09-27'],
  ['2026-10-01', '2026-10-07'],
];

function readStore(name) {
  const storePath = LEGACY_STORE_DIR_NAMES
    .map((dirName) => path.join(process.env.HOME, 'Library', 'Application Support', dirName, `${name}.json`))
    .find((candidate) => fs.existsSync(candidate));

  if (!storePath) {
    return {};
  }

  const data = fs.readFileSync(storePath);
  if (!data.length) {
    return {};
  }

  const text = decryptLegacyStore(data);
  return JSON.parse(text);
}

function decryptLegacyStore(data) {
  const plainText = data.toString('utf8');
  if (plainText.trimStart().startsWith('{')) {
    return plainText;
  }

  const initializationVector = data.subarray(0, 16);
  const encryptedData = data.subarray(17);
  for (const key of ENCRYPTION_KEYS) {
    try {
      const password = crypto.pbkdf2Sync(key, initializationVector.toString(), 10_000, 32, 'sha512');
      const decipher = crypto.createDecipheriv('aes-256-cbc', password, initializationVector);
      return Buffer.concat([decipher.update(encryptedData), decipher.final()]).toString('utf8');
    } catch {
      // Try the next known legacy key.
    }
  }
  return plainText;
}

function normalizeNumber(value, fallback = 0) {
  const numberValue = Number(value);
  return Number.isFinite(numberValue) ? numberValue : fallback;
}

function normalizeDate(date) {
  if (!date) return '';
  const parsed = new Date(`${date}T00:00:00`);
  if (Number.isNaN(parsed.getTime())) return '';
  return parsed.toISOString().slice(0, 10);
}

function isFundTradingDay(date) {
  const normalized = normalizeDate(date);
  if (!normalized) return false;
  const day = new Date(`${normalized}T00:00:00`).getDay();
  const isWeekend = day === 0 || day === 6;
  const isHoliday = MARKET_CLOSED_RANGES.some(([start, end]) => normalized >= start && normalized <= end);
  return !isWeekend && !isHoliday;
}

function addDays(date, days) {
  const parsed = new Date(`${normalizeDate(date)}T00:00:00`);
  parsed.setDate(parsed.getDate() + days);
  return parsed.toISOString().slice(0, 10);
}

function getNextFundTradingDay(date) {
  let currentDate = normalizeDate(date);
  do {
    currentDate = addDays(currentDate, 1);
  } while (!isFundTradingDay(currentDate));
  return currentDate;
}

function calcIncomeStartDate(positionDate, positionTimeType, fallback) {
  const normalizedPositionDate = normalizeDate(positionDate);
  if (!normalizedPositionDate || !positionTimeType) return fallback || null;
  const acceptedTradeDate =
    positionTimeType === 'before15' && isFundTradingDay(normalizedPositionDate)
      ? normalizedPositionDate
      : getNextFundTradingDay(normalizedPositionDate);
  return getNextFundTradingDay(acceptedTradeDate);
}

function statusForFund(fund, today, incomeStartDate) {
  if (normalizeNumber(fund.cyfe) > 0) {
    return 'holding';
  }
  if (incomeStartDate && incomeStartDate > today) {
    return 'pending';
  }
  return 'watch';
}

function shortDateText(fund) {
  const date = fund.positionDate || fund.incomeStartDate || '';
  if (/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return `${date.slice(5)} 15:00`;
  }
  return date || '--';
}

function migrate() {
  const dryRun = process.argv.includes('--dry-run');
  const config = readStore('config');
  const state = readStore('state');
  const wallets = Array.isArray(config.WALLET_SETTING) ? config.WALLET_SETTING : [];
  const currentWalletCode = config.CURRENT_WALLET_CODE || wallets[0]?.code || '-1';
  const currentWallet = wallets.find((wallet) => wallet.code === currentWalletCode) || wallets[0] || {};
  const today = new Date().toISOString().slice(0, 10);
  const fundsConfig = Array.isArray(currentWallet.funds) ? currentWallet.funds : [];

  const funds = fundsConfig.map((fund) => {
    const shares = normalizeNumber(fund.cyfe);
    const cost = normalizeNumber(fund.cbj);
    const principal = shares * cost;
    const incomeStartDate = calcIncomeStartDate(fund.positionDate, fund.positionTimeType, fund.incomeStartDate);
    const lot =
      shares > 0 && cost > 0
        ? {
            id: `${fund.code || ''}-legacy`,
            shares,
            cost,
            incomeStartDate,
            positionDate: fund.positionDate || null,
            positionTimeType: fund.positionTimeType || null,
          }
        : null;
    return {
      code: String(fund.code || ''),
      name: fund.name || fund.code || '未命名基金',
      dateText: shortDateText(fund),
      todayIncome: 0,
      todayRate: 0,
      holdingRate: null,
      status: statusForFund(fund, today, incomeStartDate),
      isUpdated: false,
      migratedShares: shares,
      migratedCost: cost,
      migratedPrincipal: Number(principal.toFixed(2)),
      incomeStartDate,
      positionMode: fund.positionMode || null,
      positionDate: fund.positionDate || null,
      positionTimeType: fund.positionTimeType || null,
      ...(lot ? { lots: [lot] } : {}),
    };
  });

  const totalAmount = funds.reduce((sum, fund) => sum + fund.migratedPrincipal, 0);
  const pendingCount = funds.filter((fund) => fund.status === 'pending').length;
  const snapshot = {
    updateTime: new Date().toISOString(),
    totalAmount: Number(totalAmount.toFixed(2)),
    holdingIncome: 0,
    holdingIncomeRate: 0,
    todayIncome: 0,
    todayIncomeRate: 0,
    pendingCount,
    funds,
    migration: {
      source: 'legacy-store',
      currentWalletCode,
      walletName: currentWallet.name || '默认钱包',
      eyeStatus: state.EYE_STATUS ?? true,
    },
  };

  if (!dryRun) {
    fs.mkdirSync(appDataDir, { recursive: true });
    fs.writeFileSync(outputPath, `${JSON.stringify(snapshot, null, 2)}\n`);
    console.log(`Wrote ${outputPath}`);
  } else {
    console.log(`Dry run: would write ${outputPath}`);
  }
  console.log(`Migrated ${funds.length} funds from wallet "${snapshot.migration.walletName}"`);
}

try {
  migrate();
} catch (error) {
  console.error(error);
  process.exit(1);
}
