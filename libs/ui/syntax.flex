// Portable views use the same AST frontend and update-code generator as Monolith.
import "internal/syntax.flex";
fn transform_syntax(context,version){return sx_transform(context,version,1);}
