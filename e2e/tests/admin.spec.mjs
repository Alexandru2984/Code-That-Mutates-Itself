import {test,expect} from '@playwright/test'

test.use({httpCredentials:{username:'admin',password:'secret',origin:'http://127.0.0.1:4003'}})

test('LiveDashboard connects under strict CSP with nonce-authorized inline scripts',async({page})=>{
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
  const response=await page.goto('/admin/dashboard');
  expect(response.headers()['content-security-policy']).toContain("'nonce-");
  expect(response.headers()['content-security-policy']).not.toContain("script-src 'self' 'unsafe-inline'");
  await expect(page.locator('.phx-connected')).toBeVisible();
  await expect(page).toHaveTitle(/LiveDashboard/);
  expect(errors).toEqual([]);
});
