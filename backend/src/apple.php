<?php
declare(strict_types=1);

// A fresh Apple authorization code is exchanged only when deleting the
// account. Provider tokens are never stored or returned to the app.
function apple_revoke_code(string $code, string $subject): void {
    $keyFile=envv('APPLE_KEY_FILE','/run/secrets/apple_key.p8');
    $team=envv('APPLE_TEAM_ID'); $kid=envv('APPLE_KEY_ID');
    if (!$team || !$kid || !is_readable($keyFile)) fail('apple_setup','Apple hesap silme servisi hazırlanıyor. Destek ekibine yazabilirsin.',503);
    $now=time();
    $secret=Firebase\JWT\JWT::encode(['iss'=>$team,'iat'=>$now,'exp'=>$now+1800,'aud'=>'https://appleid.apple.com','sub'=>envv('APPLE_CLIENT_ID')],file_get_contents($keyFile),'ES256',$kid);
    $request=static function(string $route,array $values): array {
        $ctx=stream_context_create(['http'=>['method'=>'POST','header'=>'Content-Type: application/x-www-form-urlencoded','content'=>http_build_query($values),'timeout'=>10,'ignore_errors'=>true]]);
        $raw=@file_get_contents('https://appleid.apple.com/auth/'.$route,false,$ctx);
        $status=$http_response_header[0]??'';
        if (!$raw && !str_contains($status,'200')) fail('apple_unavailable','Apple servisine ulaşılamadı. Yeniden dene.',503);
        $result=json_decode($raw?:'{}',true);
        if (!str_contains($status,'200') || !is_array($result) || isset($result['error'])) fail('apple_authorization','Apple ile yeniden doğrulayıp silmeyi dene.',422);
        return $result;
    };
    $params=['client_id'=>envv('APPLE_CLIENT_ID'),'client_secret'=>$secret];
    $tokens=$request('token',$params+['grant_type'=>'authorization_code','code'=>$code]);
    $claims=identity_claims('apple',(string)($tokens['id_token']??''));
    if (!hash_equals($subject,(string)($claims['sub']??''))) fail('apple_account','Hesabına bağlı Apple kimliğini kullan.',403);
    $token=$tokens['refresh_token']??$tokens['access_token']??null;
    if (!$token) fail('apple_authorization','Apple yetkisi alınamadı. Yeniden dene.',422);
    $request('revoke',$params+['token'=>$token,'token_type_hint'=>isset($tokens['refresh_token'])?'refresh_token':'access_token']);
}
