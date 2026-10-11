import json,subprocess,sys,time,urllib.request
out=json.load(open(sys.argv[1]))
fdid=out.get("front_door_id",{}).get("value") or ""
# Origin test executes on a web VM, so no public management port is required.
for region,host in out.get('origins',{}).get('value',{}).items():
    prefix=out['deployment_prefix']['value']
    rg=f'rg-{prefix}-{region}'
    vms=json.loads(subprocess.check_output(['az','vm','list','-g',rg,'-o','json'],text=True))
    web=[v for v in vms if (v.get('virtualMachineScaleSet') or {}).get('id','').endswith('-web')]
    if not web:raise SystemExit(f'No web VM found in {region}')
    result=json.loads(subprocess.check_output(['az','vm','run-command','invoke','--ids',web[0]['id'],'--command-id','RunShellScript','--scripts',f'cloud-init status --wait >/dev/null; curl -fsS --retry 12 --retry-delay 10 --retry-all-errors http://127.0.0.1/health; curl -fsS --retry 12 --retry-delay 10 --retry-all-errors -H "X-Azure-FDID: {fdid}" http://127.0.0.1/' ,'-o','json'],text=True))
    message='\n'.join(v.get('message','') for v in result.get('value',[]))
    if 'healthy' not in message or 'Kantin Tongue' not in message:raise SystemExit(f'{region}: application smoke test failed: {message}')
    print(region,': web -> internal LB -> app passed')
url=out.get('front_door_url',{}).get('value')
if url:
    for attempt in range(15):
        try:
            body=urllib.request.urlopen(url,timeout=20).read().decode()
            if 'Kantin Tongue' not in body:raise ValueError('Unexpected body')
            print('Front Door HTTPS smoke test passed');break
        except Exception:
            if attempt==14:raise
            time.sleep(20)
