import json,subprocess,sys,uuid
out=json.load(open(sys.argv[1]))
fdid=out.get('front_door_id',{}).get('value')
if not fdid:raise SystemExit('Front Door not deployed')
fdid=str(uuid.UUID(fdid))
prefix=out['deployment_prefix']['value']
config='if ($http_x_azure_fdid != "'+fdid+'") { return 403; }'
for region in out['origins']['value']:
    rg=f'rg-{prefix}-{region}'
    vms=json.loads(subprocess.check_output(['az','vm','list','-g',rg,'-o','json'],text=True))
    for v in vms:
        if not (v.get('virtualMachineScaleSet') or {}).get('id','').endswith('-web'):continue
        command="set -e; cloud-init status --wait >/dev/null; cat > /etc/nginx/snippets/frontdoor-guard.conf <<'GUARD'\n"+config+"\nGUARD\nnginx -t; systemctl reload nginx"
        result=json.loads(subprocess.check_output(['az','vm','run-command','invoke','--ids',v['id'],'--command-id','RunShellScript','--scripts',command,'-o','json'],text=True))
        messages='\n'.join(x.get('message','') for x in result.get('value',[]))
        if 'test is successful' not in messages:raise SystemExit(messages)
        print(region,v['name'],'Front Door ID guard enabled')
