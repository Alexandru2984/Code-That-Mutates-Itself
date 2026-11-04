import {test,expect} from '@playwright/test'
import {AxeBuilder} from '@axe-core/playwright'
import fs from 'node:fs/promises'

test.use({httpCredentials:{username:'admin',password:'secret',origin:'http://127.0.0.1:4003'}})

test('public exploration and world administration pass automated accessibility checks',async({page},testInfo)=>{
  test.setTimeout(90_000)
  const reports=[],failures=[]
  const scan=async(path,width,state='default')=>{
    await page.setViewportSize({width,height:900})
    const result=await new AxeBuilder({page}).withTags(['wcag2a','wcag2aa','wcag21a','wcag21aa','wcag22aa']).analyze()
    reports.push({path,width,state,violations:result.violations,incomplete:result.incomplete})
    failures.push(...result.violations.map(rule=>({path,width,state,rule:rule.id,impact:rule.impact,targets:rule.nodes.map(node=>node.target)})))
  }
  for(const path of ['/','/tree','/lab','/offline','/admin/world']){
    await page.goto(path);if(['/lab','/offline'].includes(path))await expect(page.locator('input[name=seed]')).toBeEnabled();else await expect(page.locator('.phx-connected')).toBeVisible()
    if(['/lab','/offline'].includes(path)){
      await expect(page.locator('input[name=seed]')).toBeEnabled();await page.locator('[data-missions]').evaluate(el=>el.open=true);if(await page.locator('[data-mission-stop]').isVisible())await page.locator('[data-mission-stop]').click()
      await page.locator('[data-action=save]').click();await page.locator('[data-entry-action=compare]').first().click()
      await page.locator('[data-mission-start=common-ground]').click();await page.locator('[data-share-conditions]').click()
    }
    for(const width of [360,1440]){
      await scan(path,width)
    }
    if(path==='/'){
      for(const view of ['Trait map','Network','Leaders']){
        await page.getByRole('button',{name:view,exact:true}).click();await scan(path,360,view)
      }
      await page.getByRole('button',{name:'Minds',exact:true}).click()
      await page.locator('.mind-card').first().getByRole('button',{name:'Details',exact:false}).click();await expect(page.locator('#entity-detail')).toBeVisible();await scan(path,360,'dossier')
      await page.keyboard.press('Escape');await page.getByRole('button',{name:'Field guide',exact:false}).click();await expect(page.locator('#field-guide-dialog')).toBeVisible();await scan(path,360,'guide')
    }
  }
  await fs.writeFile(testInfo.outputPath('accessibility.json'),JSON.stringify(reports,null,2))
  expect(failures).toEqual([])
})
