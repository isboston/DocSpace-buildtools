%build

cd %{_builddir}/buildtools

bash install/common/systemd/build.sh -pm "rpm"

bash install/common/build-frontend.sh --srcpath %{_builddir} -di "false"
bash install/common/build-backend.sh --srcpath %{_builddir}
bash install/common/publish-backend.sh --srcpath %{_builddir}/server
bash install/common/plugins-build.sh %{_builddir}/plugins

rename -f -v "s/product([^\/]*)$/%{product}\$1/g" install/common/*

rm -f config/nginx/onlyoffice-login.conf
find config/ -type f -regex '.*\.\(test\|dev\)\..*' -delete

if ! grep -q 'var/www/%{product}' config/nginx/*.conf; then find config/nginx/ -name "*.conf" -exec sed -i "s@\(var/www/\)@\1%{product}/@" {} +; fi

json -I -f config/appsettings.services.json -e "this.logPath=\"/var/log/onlyoffice/%{product}\"" -e "this.socket={ 'path': '../ASC.Socket.IO/' }" \
-e "this.ssoauth={ 'path': '../ASC.SsoAuth/' }" -e "this.logLevel=\"warning\""  -e "this.core={ 'products': { 'folder': '%{buildpath}/products', 'subfolder': 'server'} }"
json -I -f config/appsettings.json -e "this.core.notify.postman=\"services\"" -e "this['debug-info'].enabled=\"false\"" -e "this.web.samesite=\"None\"" -e "this.core.oidc.disableValidateToken=\"false\"" -e "this.core.oidc.showPII=\"false\"" 
json -I -f config/apisystem.json -e "this.core.notify.postman=\"services\""
json -I -f %{_builddir}/publish/web/public/scripts/config.json -e "this.wrongPortalNameUrl=\"\""

sed 's_\(minlevel=\)"[^"]*"_\1"Warn"_g' -i config/nlog.config
sed 's/teamlab.info/onlyoffice.com/g' -i config/autofac.consumers.json

sed -e 's_etc/nginx_etc/openresty_g' -e 's/listen\s\+\([0-9]\+\);/listen 127.0.0.1:\1;/g' -i config/nginx/*.conf config/nginx/includes/*.conf
sed -i "s#\$public_root#/var/www/%{product}/public/#g" config/nginx/onlyoffice.conf
sed -E 's_(http://)[^:]+(:5601)_\1localhost\2_g' -i config/nginx/onlyoffice.conf
sed -e 's/$router_host/127.0.0.1/g' -e 's/this_host\|proxy_x_forwarded_host/host/g' -e 's/proxy_x_forwarded_proto/scheme/g' -e 's_includes_/etc/openresty/includes_g' -e '/quic\|alt-svc/Id' -i install/docker/config/nginx/onlyoffice-proxy*.conf
sed -e '/.pid/d' -e '/temp_path/d' -e 's_etc/nginx_etc/openresty_g' -e 's/\.log/-openresty.log/g' -i install/docker/config/nginx/templates/nginx.conf.template
sed -i "s_\(.*root\).*;_\1 \"/var/www/%{product}\";_g" -i install/docker/config/nginx/letsencrypt.conf
sed -i "s#\(/var/log/onlyoffice/\)#\1%{product}#" install/docker/config/fluent-bit.conf
sed -i '/^\[OUTPUT\]/i\[INPUT]' install/docker/config/fluent-bit.conf
sed -i '/^\[OUTPUT\]/i\    Name                exec' install/docker/config/fluent-bit.conf
sed -i '/^\[OUTPUT\]/i\    Interval_Sec        86400' install/docker/config/fluent-bit.conf
sed -i '/^\[OUTPUT\]/i\    Command             curl -s -X POST OPENSEARCH_SCHEME://OPENSEARCH_HOST:OPENSEARCH_PORT/OPENSEARCH_INDEX/_delete_by_query -H '\''Content-Type: application/json'\'' -d '\''{"query": {"range": {"@timestamp": {"lt": "now-30d"}}}}'\''' install/docker/config/fluent-bit.conf 
sed -i '/^\[OUTPUT\]/i\\' install/docker/config/fluent-bit.conf

rename -f -v 's/(.*\.(community|enterprise|developer))\.json$/$1.json.template/' config/*.json
sed -i 's_app/onlyoffice/data_var/www/onlyoffice/Data_g' config/*.json.template

find %{_builddir}/server/publish/ \
     %{_builddir}/server/ASC.Migration.Runner \
     -depth -type f -regex '.*\(dll\|dylib\|so\)$' -exec chmod 755 {} \;

find %{_builddir}/server/publish/ \
     %{_builddir}/server/ASC.Migration.Runner \
     -depth -type f -regex '.*\(so\)$' -exec strip {} \;
