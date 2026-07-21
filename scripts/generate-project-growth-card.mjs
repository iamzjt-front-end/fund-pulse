#!/usr/bin/env node

import path from "node:path";

import { generateGrowthCards } from "./lib/project-growth-card.mjs";

function usage() {
  return "Usage: node scripts/generate-project-growth-card.mjs --repo owner/repository --output-dir directory";
}

function readArguments(argv) {
  if (argv.includes("--help") || argv.includes("-h")) {
    return { help: true };
  }

  const values = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument !== "--repo" && argument !== "--output-dir") {
      throw new Error(`Unknown argument: ${argument}\n${usage()}`);
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for ${argument}\n${usage()}`);
    }
    values[argument.slice(2)] = value;
    index += 1;
  }
  return {
    repository: values.repo,
    outputDirectory: values["output-dir"],
  };
}

async function main() {
  const options = readArguments(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }

  const result = await generateGrowthCards({
    ...options,
    outputDirectory: options.outputDirectory ? path.resolve(options.outputDirectory) : undefined,
    token: process.env.GITHUB_TOKEN,
  });

  console.log(`Growth cards updated: ${result.data.stars} stars, +${result.data.stars7d} in 7d, +${result.data.stars30d} in 30d`);
  console.log(`Light: ${result.outputs.light}`);
  console.log(`Dark: ${result.outputs.dark}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
