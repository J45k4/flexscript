fn text_size(text) {
    let size = 0;
    while load8(text + size) { size = size + 1; }
    return size;
}
