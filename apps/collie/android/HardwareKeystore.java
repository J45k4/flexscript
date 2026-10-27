package org.flexscript.collie;

import android.content.pm.PackageManager;
import android.os.Build;
import android.security.keystore.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.spec.ECGenParameterSpec;
import java.util.*;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.ReentrantLock;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;
import org.json.*;

/** Android Keystore objects and cryptographic operations; private keys never leave it. */
final class HardwareKeystore {
    private static final String PROVIDER="AndroidKeyStore";
    private static final ReentrantLock MUTATION=new ReentrantLock();
    static boolean supports(String op){switch(op){case "key_list":case "key_info":case "key_generate":case "key_public":case "key_sign":case "key_verify":case "key_encrypt":case "key_decrypt":case "key_delete":return true;default:return false;}}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{out.put(VmHardware.capability("keystore",true,true,"keystore"));boolean strongbox=Build.VERSION.SDK_INT>=28&&c.host.getPackageManager().hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE);out.put(VmHardware.capability("keystore_strongbox",strongbox,strongbox,"keystore"));}
    static KeyStore store()throws Exception{KeyStore store=KeyStore.getInstance(PROVIDER);store.load(null);return store;}
    static String prefix(VmHardware.Context c)throws Exception{byte[] digest=MessageDigest.getInstance("SHA-256").digest(c.root.getCanonicalPath().getBytes(StandardCharsets.UTF_8));StringBuilder out=new StringBuilder("collie-hw-v1-");for(byte b:digest)out.append(String.format(Locale.ROOT,"%02x",b&255));return out.append(':').toString();}
    static String alias(JSONArray args,int index)throws Exception{String alias=VmHardware.text(args,index,64);if(!alias.matches("[A-Za-z0-9._-]{1,64}"))throw new VmHardware.Failure("invalid_argument","Key aliases must contain 1..64 letters, digits, dots, underscores or hyphens.");return alias;}
    static List<String> aliases(KeyStore store,String prefix)throws Exception{ArrayList<String> out=new ArrayList<>();Enumeration<String> aliases=store.aliases();while(aliases.hasMoreElements()){String name=aliases.nextElement();if(name.startsWith(prefix))out.add(name.substring(prefix.length()));}Collections.sort(out);return out;}
    static Key key(KeyStore store,String name)throws Exception{Key key=store.getKey(name,null);if(key==null)throw new VmHardware.Failure("not_found","No such key in this workspace.");return key;}
    static KeyInfo metadata(Key key)throws Exception{if(key instanceof SecretKey)return (KeyInfo)SecretKeyFactory.getInstance(key.getAlgorithm(),PROVIDER).getKeySpec((SecretKey)key,KeyInfo.class);return KeyFactory.getInstance(key.getAlgorithm(),PROVIDER).getKeySpec(key,KeyInfo.class);}
    static JSONObject info(KeyStore store,String name,String alias)throws Exception{Key key=key(store,name);KeyInfo info=metadata(key);String level=info.isInsideSecureHardware()?"hardware":"software";if(Build.VERSION.SDK_INT>=31){int security=info.getSecurityLevel();level=security==KeyProperties.SECURITY_LEVEL_STRONGBOX?"strongbox":security==KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT?"trusted_environment":security==KeyProperties.SECURITY_LEVEL_SOFTWARE?"software":"unknown";}Date created=store.getCreationDate(name);return VmHardware.object("alias",alias,"algorithm",key.getAlgorithm(),"size_bits",info.getKeySize(),"security_level",level,"inside_secure_hardware",info.isInsideSecureHardware(),"origin",info.getOrigin(),"authentication_required",info.isUserAuthenticationRequired(),"private_exportable",false,"created_ms",created==null?JSONObject.NULL:created.getTime());}
    private static Object generate(VmHardware.Context c,KeyStore store,String prefix,String alias,String kind,String backing)throws Exception{
        if(!backing.equals("any")&&!backing.equals("hardware")&&!backing.equals("strongbox"))throw new VmHardware.Failure("invalid_argument","Backing must be any, hardware or strongbox. Required hardware never silently falls back to software.");
        if(!Arrays.asList("ec_p256","rsa2048","aes256","hmac_sha256").contains(kind))throw new VmHardware.Failure("invalid_argument","Key kind must be ec_p256, rsa2048, aes256 or hmac_sha256.");
        if(backing.equals("strongbox")&&(Build.VERSION.SDK_INT<28||!c.host.getPackageManager().hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)))throw new VmHardware.Failure("unsupported","This device does not advertise StrongBox Keystore.");
        if(!MUTATION.tryLock(1,TimeUnit.SECONDS))throw new VmHardware.Failure("busy","Another keystore mutation is still completing.");String name=prefix+alias;boolean created=false,committed=false;
        try{
            VmHardware.check();if(store.containsAlias(name))throw new VmHardware.Failure("already_exists","Key alias already exists; delete explicitly before replacing it.");if(aliases(store,prefix).size()>=32)throw new VmHardware.Failure("resource_limit","At most 32 keys may be stored in one workspace.");
            boolean symmetric=kind.equals("aes256")||kind.equals("hmac_sha256");String algorithm=kind.equals("ec_p256")?KeyProperties.KEY_ALGORITHM_EC:kind.equals("rsa2048")?KeyProperties.KEY_ALGORITHM_RSA:kind.equals("aes256")?KeyProperties.KEY_ALGORITHM_AES:KeyProperties.KEY_ALGORITHM_HMAC_SHA256;
            int purposes=kind.equals("aes256")?KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT:KeyProperties.PURPOSE_SIGN|KeyProperties.PURPOSE_VERIFY;
            KeyGenParameterSpec.Builder spec=new KeyGenParameterSpec.Builder(name,purposes).setUserAuthenticationRequired(false);
            if(kind.equals("ec_p256"))spec.setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1")).setDigests(KeyProperties.DIGEST_SHA256);
            if(kind.equals("rsa2048"))spec.setKeySize(2048).setDigests(KeyProperties.DIGEST_SHA256).setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1);
            if(kind.equals("aes256"))spec.setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setRandomizedEncryptionRequired(true);
            if(kind.equals("hmac_sha256"))spec.setKeySize(256).setDigests(KeyProperties.DIGEST_SHA256);
            if(backing.equals("strongbox"))spec.setIsStrongBoxBacked(true);
            // Alias is known absent while the mutation lock is held. Cleanup is
            // safe even if generation fails after Android has written an entry.
            created=true;
            if(symmetric){KeyGenerator generator=KeyGenerator.getInstance(algorithm,PROVIDER);generator.init(spec.build());generator.generateKey();}
            else{KeyPairGenerator generator=KeyPairGenerator.getInstance(algorithm,PROVIDER);generator.initialize(spec.build());generator.generateKeyPair();}
            VmHardware.check();JSONObject result=info(store,name,alias);if(!backing.equals("any")&&!result.getBoolean("inside_secure_hardware"))throw new VmHardware.Failure("hardware_unavailable","Android created a software key; required hardware backing is unavailable. The key was removed.");
            if(backing.equals("strongbox")&&Build.VERSION.SDK_INT>=31&&!result.getString("security_level").equals("strongbox"))throw new VmHardware.Failure("hardware_unavailable","Android did not report StrongBox backing. The key was removed.");
            committed=true;return result;
        }catch(StrongBoxUnavailableException error){throw new VmHardware.Failure("hardware_unavailable","StrongBox could not create this key; no software fallback was accepted.");}
        finally{try{if(created&&!committed)store.deleteEntry(name);}finally{MUTATION.unlock();}}
    }
    private static byte[] sign(Key key,byte[] data)throws Exception{
        if(key instanceof SecretKey){if(!key.getAlgorithm().equalsIgnoreCase("HmacSHA256"))throw new VmHardware.Failure("wrong_key_type","Signing requires EC, RSA or HMAC-SHA256.");Mac mac=Mac.getInstance("HmacSHA256");mac.init(key);return mac.doFinal(data);}
        String algorithm=key.getAlgorithm().equals("EC")?"SHA256withECDSA":"SHA256withRSA";Signature signature=Signature.getInstance(algorithm);signature.initSign((PrivateKey)key);signature.update(data);return signature.sign();
    }
    static Object call(VmHardware.Context c,String op,JSONArray args)throws Exception{
        KeyStore store=store();String prefix=prefix(c);
        if(op.equals("key_list")){int offset=VmHardware.integer(args,0,0,100000),limit=VmHardware.integer(args,1,1,32);List<String> names=aliases(store,prefix);int end=Math.min(names.size(),offset+limit);JSONArray out=new JSONArray();for(int i=offset;i<end;i++)out.put(names.get(i));return VmHardware.object("aliases",out,"next",end<names.size()?end:-1,"total",names.size());}
        String alias=alias(args,0),name=prefix+alias;
        if(op.equals("key_generate"))return generate(c,store,prefix,alias,VmHardware.text(args,1,32),VmHardware.text(args,2,16));
        if(op.equals("key_info"))return info(store,name,alias);
        if(op.equals("key_delete")){if(!MUTATION.tryLock(1,TimeUnit.SECONDS))throw new VmHardware.Failure("busy","Another keystore mutation is still completing.");try{VmHardware.check();boolean exists=store.containsAlias(name);if(exists)store.deleteEntry(name);return exists?1:0;}finally{MUTATION.unlock();}}
        Key key=key(store,name);
        if(op.equals("key_public")){java.security.cert.Certificate certificate=store.getCertificate(name);if(certificate==null)throw new VmHardware.Failure("wrong_key_type","Symmetric keys have no public key; private/secret key material cannot be exported.");return VmHardware.bytes(certificate.getPublicKey().getEncoded());}
        if(op.equals("key_sign"))return VmHardware.bytes(sign(key,VmHardware.data(args.get(1))));
        if(op.equals("key_verify")){
            byte[] data=VmHardware.data(args.get(1)),bytes=VmHardware.data(args.get(2));if(bytes.length>1024)throw new VmHardware.Failure("size_limit","Signature must fit in 1024 bytes; signed data may use the full 32 KiB.");
            if(key instanceof SecretKey)return MessageDigest.isEqual(sign(key,data),bytes)?1:0;
            Signature signature=Signature.getInstance(key.getAlgorithm().equals("EC")?"SHA256withECDSA":"SHA256withRSA");signature.initVerify(store.getCertificate(name).getPublicKey());signature.update(data);try{return signature.verify(bytes)?1:0;}catch(SignatureException malformed){return 0;}
        }
        if(!key.getAlgorithm().equals("AES"))throw new VmHardware.Failure("wrong_key_type","Encryption/decryption requires an AES key.");
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");
        if(op.equals("key_encrypt")){byte[] data=VmHardware.data(args.get(1)),aad=VmHardware.data(args.get(2));if(data.length+aad.length>VmHardware.MAX_BYTES-16)throw new VmHardware.Failure("size_limit","Plaintext and additional data together must fit in 32752 bytes.");cipher.init(Cipher.ENCRYPT_MODE,key);cipher.updateAAD(aad);byte[] ciphertext=cipher.doFinal(data);return VmHardware.object("nonce",VmHardware.bytes(cipher.getIV()),"ciphertext",VmHardware.bytes(ciphertext));}
        if(op.equals("key_decrypt")){byte[] nonce=VmHardware.data(args.get(1)),ciphertext=VmHardware.data(args.get(2)),aad=VmHardware.data(args.get(3));if(nonce.length!=12||ciphertext.length<16)throw new VmHardware.Failure("invalid_argument","AES-GCM requires a 12-byte nonce and a ciphertext containing the 16-byte tag.");if(ciphertext.length+aad.length>VmHardware.MAX_BYTES)throw new VmHardware.Failure("size_limit","Ciphertext and additional data together must fit in 32 KiB.");cipher.init(Cipher.DECRYPT_MODE,key,new GCMParameterSpec(128,nonce));cipher.updateAAD(aad);try{return VmHardware.bytes(cipher.doFinal(ciphertext));}catch(AEADBadTagException invalid){throw new VmHardware.Failure("authentication_failed","Ciphertext or additional data failed authentication.");}}
        throw new VmHardware.Failure("unsupported_operation","Unknown keystore operation.");
    }
}
