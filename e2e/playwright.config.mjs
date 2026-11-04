import {defineConfig} from '@playwright/test'
import {fileURLToPath} from 'node:url'

export default defineConfig({
  testDir:'./tests',
  workers:1,
  retries:process.env.CI?1:0,
  timeout:30_000,
  use:{baseURL:'http://127.0.0.1:4003',trace:'retain-on-failure',
    launchOptions:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH?{executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH}:{}},
  webServer:{command:'MIX_ENV=test mix run --no-start ../e2e/preview.exs',
    cwd:fileURLToPath(new URL('../evolving_minds',import.meta.url)),
    url:'http://127.0.0.1:4003/healthz',timeout:60_000,reuseExistingServer:false},
  reporter:process.env.CI?'github':'list'
})
