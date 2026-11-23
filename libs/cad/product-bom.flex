// Product and wire-stock procurement for a standalone PCAD document.
import "studio/pcad-bom.flex";
import "studio/pcad-bom-csv.flex";

fn cad_pcad_product_bom(document) {
    cg_begin();
    let resolved=pcad_resolve(document);
    if !resolved {return ca_error();}
    return pdb_product(resolved);
}
