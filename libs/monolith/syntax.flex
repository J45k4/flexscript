// HTML compatibility frontend. The shared parser builds a UI AST before lowering.
import "../ui/internal/syntax.flex";
fn transform_syntax(context,version){return sx_transform(context,version,0);}
