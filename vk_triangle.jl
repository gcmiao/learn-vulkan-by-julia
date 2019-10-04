using VulkanCore
using GLFW

WIDTH = 640
HEIGHT = 480
window = GLFW.Window
instance = Ref{vk.VkInstance}()
physicalDevice = vk.VK_NULL_HANDLE
logicalDevice = Ref{vk.VkDevice}()
graphicsQueue = Ref{vk.VkQueue}()
surface = vk.VkSurfaceKHR
presentQueue = Ref{vk.VkQueue}()
requiredExtensions = [vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME]
swapChain = Ref{vk.VkSwapchainKHR}()
swapChainImageFormat = vk.VkFormat
swapChainExtent = vk.VkExtent2D
swapChainImages = Vector{vk.VkImage}()
swapChainImageViews = Vector{vk.VkImageView}()
renderPass = Ref{vk.VkRenderPass}()
pipelineLayout = Ref{vk.VkPipelineLayout}()
graphicsPipeline = Ref{vk.VkPipeline}()
swapChainFramebuffers = Vector{vk.VkFramebuffer}()
commandPool = Ref{vk.VkCommandPool}()
commandBuffers = Vector{vk.VkCommandBuffer}()
MAX_FRAMES_IN_FLIGHT = 2
currentFrame = 1
imageAvailableSemaphores = Vector{vk.VkSemaphore}()
renderFinishedSemaphores = Vector{vk.VkSemaphore}()
inFlightFences = Vector{vk.VkFence}()

#################### 1.Create instance ####################
function getAppInfo()
    appInfo = Ref(vk.VkApplicationInfo(
        vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        C_NULL, #pNext
        pointer("Hello Triangle"),
        vk.VK_MAKE_VERSION(1, 0, 0),
        pointer("No Engine"),
        vk.VK_MAKE_VERSION(1, 0, 0),
        vk.VK_API_VERSION_1_0()
    ))
end

strings2pp(names::Vector{String}) = (ptr = Base.cconvert(Ptr{Cstring}, names); GC.@preserve ptr Base.unsafe_convert(Ptr{Cstring}, ptr))

function getCreateInfo(appInfo::Ref{vk.VkApplicationInfo})
    glfwExtensions = GLFW.GetRequiredInstanceExtensions()
    extensionCount = length(glfwExtensions)

    createInfo = Ref(vk.VkInstanceCreateInfo(
        vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        C_NULL, #pNext
        UInt32(0), #flags
        Base.unsafe_convert(Ptr{vk.VkApplicationInfo}, appInfo),
        0, #layerCount
        C_NULL, #layerNames
        extensionCount,
        strings2pp(glfwExtensions)
    ))
    createInfo
end

function createInstance()
    appInfo = getAppInfo()
    createInfo = getCreateInfo(appInfo)
    err = vk.vkCreateInstance(createInfo, C_NULL, instance)
    println(err)
    err
end

#################### 2.Using validation layers ####################
#################### 3.Pick Physical device ####################
function checkDeviceExtensionSupport(device)
    extensionCount = Ref{UInt32}(0)
    vk.vkEnumerateDeviceExtensionProperties(device, C_NULL, extensionCount, C_NULL)

    availableExtensions = Vector{vk.VkExtensionProperties}(undef, extensionCount[])
    vk.vkEnumerateDeviceExtensionProperties(device, C_NULL, extensionCount, availableExtensions)

    deviceExtensions = Set(requiredExtensions)
    supportAll = true
    for extension in availableExtensions
        nameChars = UInt8[extension.extensionName...]
        extensionName = String(Base.getindex(nameChars, 1:Base.findfirst(x->x==0, nameChars) - 1))
        delete!(deviceExtensions, extensionName)
        #delete!(deviceExtensions, String(filter(x->x!=0, UInt8[extension.extensionName...])))
    end
    return length(deviceExtensions) == 0
end

function isDeviceSuitable(device::vk.VkPhysicalDevice)
    deviceProperties = Ref{vk.VkPhysicalDeviceProperties}()
    deviceFeatures = Ref{vk.VkPhysicalDeviceFeatures}()
    vk.vkGetPhysicalDeviceProperties(device, deviceProperties)
    vk.vkGetPhysicalDeviceFeatures(device, deviceFeatures)
    if (deviceFeatures[].geometryShader
        #&&deviceProperties[].deviceType == vk.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
        ) == vk.VK_FALSE
        return false
    end

    extensionsSupported = checkDeviceExtensionSupport(device)
    if !extensionsSupported
        println("does not support required extensions!")
        return false
    end

    swapChainAdequate = false
    swapChainSupport = querySwapChainSupport(device)
    swapChainAdequate = length(swapChainSupport.formats) > 0 && length(swapChainSupport.presentModes) > 0
    if !swapChainAdequate
        println("swap chain is not adequate!")
        return false
    end

    indices = findQueueFamilies(device)
    if !QueueFamilyIndices_isComplete(indices)
        println("queue family indices is not complete!")
        return false
    end
    true
end

function pickPhysicalDevice()
    deviceCount = Ref{Cuint}(0)
    vk.vkEnumeratePhysicalDevices(instance[], deviceCount, C_NULL)
    if (deviceCount[] == 0)
        println("failed to find GPUs with Vulkan support!")
    end

    devices = Vector{vk.VkPhysicalDevice}(undef, deviceCount[])
    vk.vkEnumeratePhysicalDevices(instance[], deviceCount, devices)

    for device in devices
        if (isDeviceSuitable(device))
            global physicalDevice = device
            break
        end
    end
    if (physicalDevice == vk.VK_NULL_HANDLE)
        println("failed to find a suitable GPU!")
    end
end

#################### 4.Queue families ####################
mutable struct QueueFamilyIndices
    graphicsFamily::Int32
    presentFamily::Int32

    QueueFamilyIndices() = new(-1, -1)
end

function QueueFamilyIndices_isComplete(this)
    this.graphicsFamily != -1 && this.presentFamily != -1
end

function findQueueFamilies(device::vk.VkPhysicalDevice)
    queueFamilyCount = Ref{Cuint}(0)
    vk.vkGetPhysicalDeviceQueueFamilyProperties(device, queueFamilyCount, C_NULL)
    
    queueFamilies = Vector{vk.VkQueueFamilyProperties}(undef, queueFamilyCount[])
    vk.vkGetPhysicalDeviceQueueFamilyProperties(device, queueFamilyCount, queueFamilies)
    
    
    indices = QueueFamilyIndices()
    i = 0 #queueFamilyIndex should start from 0
    for queueFamily in queueFamilies
        if (queueFamily.queueCount > 0)
            if(queueFamily.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT == 1)
                indices.graphicsFamily = i
            end
            
            presentSupport = Ref{vk.VkBool32}(false)
            vk.vkGetPhysicalDeviceSurfaceSupportKHR(device, i, surface, presentSupport)
            if(presentSupport[] == vk.VK_TRUE)
                indices.presentFamily = i
            end
        end

        if (QueueFamilyIndices_isComplete(indices))
            break
        end
        i += 1
    end
    indices
end

#################### 5.Create logical device ####################
function createLogicalDevice()
    indices = findQueueFamilies(physicalDevice)

    queueCreateInfos = Vector{vk.VkDeviceQueueCreateInfo}(undef, 0)
    uniqueQueueFamilies = Set([indices.graphicsFamily, indices.presentFamily])

    for queueFamily in uniqueQueueFamilies
        queuePriority = Ref{Float32}(1.0)
        queueCreateInfo = vk.VkDeviceQueueCreateInfo(
            vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            C_NULL,
            0, #flag
            queueFamily, #queueFamilyIndex
            1, #queueCount
            Base.unsafe_convert(Ptr{Float32}, queuePriority)
        )
        push!(queueCreateInfos, queueCreateInfo)
    end

    deviceFeatures = Ref{vk.VkPhysicalDeviceFeatures}()
    vk.vkGetPhysicalDeviceFeatures(physicalDevice, deviceFeatures)

    flags = vk.VK_DEBUG_REPORT_ERROR_BIT_EXT |
    vk.VK_DEBUG_REPORT_WARNING_BIT_EXT |
    vk.VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT

    createInfo = Ref(vk.VkDeviceCreateInfo(
        vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        C_NULL,
        #0, #flags
        flags,
        length(queueCreateInfos), #createInfoCount
        pointer(queueCreateInfos),
        0, #enabledLayerCount, VilidationLayers is disabled
        C_NULL, #ppEnabledlayerNames
        length(requiredExtensions), #enabledExtensionCount
        strings2pp(requiredExtensions), #ppEnabledExtensionNames
        Base.unsafe_convert(Ptr{vk.VkPhysicalDeviceFeatures}, deviceFeatures)
    ))
    println("ready")
    GC.@preserve createInfo begin
        err = vk.vkCreateDevice(physicalDevice, createInfo, C_NULL, logicalDevice)
        if err != vk.VK_SUCCESS
            println(err)
            println("failed to create logical device!")
        end
    end

    vk.vkGetDeviceQueue(logicalDevice[], indices.graphicsFamily, 0, graphicsQueue)
    vk.vkGetDeviceQueue(logicalDevice[], indices.presentFamily, 0, presentQueue)
end

#################### 6.Create window surface ####################
function createSurface()
    global surface = GLFW.CreateWindowSurface(instance[], window)
end

#################### 7.Swap chain ####################
mutable struct SwapChainSupportDetails
    capabilities::Ref{vk.VkSurfaceCapabilitiesKHR}
    formats::Vector{vk.VkSurfaceFormatKHR}
    presentModes::Vector{vk.VkPresentModeKHR}

    SwapChainSupportDetails() = new(Ref{vk.VkSurfaceCapabilitiesKHR}(),
                                    Vector{vk.VkSurfaceFormatKHR}(undef, 1),
                                    Vector{vk.VkPresentModeKHR}(undef, 1))
end

function querySwapChainSupport(device::vk.VkPhysicalDevice)
    details = SwapChainSupportDetails()
    vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, details.capabilities)
    formatCount = Ref{UInt32}()
    vk.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, formatCount, C_NULL)
    if (formatCount[] != 0)
        resize!(details.formats, formatCount[])
        vk.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, formatCount, details.formats)
    end

    presentModeCount = Ref{UInt32}()
    vk.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, presentModeCount, C_NULL)
    if (presentModeCount != 0)
        resize!(details.presentModes, presentModeCount[])
        vk.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, presentModeCount, details.presentModes)
    end
    return details
end

function chooseSwapSurfaceFormat(availableFormats::Vector{vk.VkSurfaceFormatKHR})
    if (length(availableFormats) == 1 && availableFormats[0].format == vk.VK_FORMAT_UNDEFINED)
        return [vk.VK_FORMAT_B8G8R8A8_UNORM, vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR]
    end

    for availableFormat in availableFormats
        if (availableFormat.format == vk.VK_FORMAT_B8G8R8A8_UNORM && availableFormat.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
            return availableFormat
        end
    end
    return availableFormats[0]
end

function chooseSwapPresentMode(availablePresentModes::Vector{vk.VkPresentModeKHR})
    bestMode = vk.VK_PRESENT_MODE_FIFO_KHR
    for availablePresentMode in availablePresentModes
        if availablePresentMode == vk.VK_PRESENT_MODE_MAILBOX_KHR
            return availablePresentMode
        elseif availablePresentMode == vk.VK_PRESENT_MODE_IMMEDIATE_KHR
            bestMode = availablePresentMode
        end
    end
    return bestMode
end

function chooseSwapExtent(capabilities::vk.VkSurfaceCapabilitiesKHR)
    if capabilities.currentExtent.width != typemax(UInt32)
        return capabilities.currentExtent
    else
        actualExtent = vk.VkExtent2D(WIDTH, HEIGHT)
        actualExtent.width = max(capabilities.minImageExtent.width, min(capabilities.maxImageExtent.width, actualExtent.width))
        actualExtent.height = max(capabilities.minImageExtent.height, min(capabilities.maxImageExtent.height, actualExtent.height))
        return actualExtent
    end
end

function createSwapChain()
    swapChainSupport = querySwapChainSupport(physicalDevice)
    surfaceFormat = chooseSwapSurfaceFormat(swapChainSupport.formats)
    presentMode = chooseSwapPresentMode(swapChainSupport.presentModes)
    global swapChainExtent = chooseSwapExtent(swapChainSupport.capabilities[])

    imageCount = swapChainSupport.capabilities[].minImageCount + 1
    if (swapChainSupport.capabilities[].maxImageCount > 0 && imageCount > swapChainSupport.capabilities[].maxImageCount)
        imageCount = swapChainSupport.capabilities[].maxImageCount
    end
    global swapChainImageFormat = surfaceFormat.format

    indices = findQueueFamilies(physicalDevice)

    imageSharingMode = vk.VK_SHARING_MODE_EXCLUSIVE
    queueFamilyIndexCount = 0 # Optional
    queueFamilyIndices = C_NULL # Optional
    if (indices.graphicsFamily != indices.presentFamily)
        imageSharingMode = vk.VK_SHARING_MODE_CONCURRENT
        queueFamilyIndexCount = 2
        queueFamilyIndices = [indices.graphicsFamily, indices.presentFamily]
    end

    createInfo = Ref(vk.VkSwapchainCreateInfoKHR(
        vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR, #sType
        C_NULL, #pNext
        vk.VkFlags(0), #flags
        surface, #surface
        imageCount, #minImageCount
        swapChainImageFormat, #imageFormat
        surfaceFormat.colorSpace, #imageColorSpace
        swapChainExtent, #imageExtent
        1, #imageArrayLayers
        vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT, #imageUsage
        imageSharingMode, #imageSharingMode::VkSharingMode
        queueFamilyIndexCount, #queueFamilyIndexCount::UInt32
        queueFamilyIndices, #pQueueFamilyIndices::Ptr{UInt32}
        swapChainSupport.capabilities[].currentTransform, #preTransform::VkSurfaceTransformFlagBitsKHR
        vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR, #compositeAlpha::VkCompositeAlphaFlagBitsKHR
        presentMode, #presentMode::VkPresentModeKHR
        vk.VK_TRUE, #clipped::VkBool32
        vk.VK_NULL_HANDLE #oldSwapchain::VkSwapchainKHR
    ))

    if (vk.vkCreateSwapchainKHR(logicalDevice[], createInfo, C_NULL, swapChain) != vk.VK_SUCCESS)
        println("failed to create swap chain!")
    end

    imageCount = Ref{UInt32}()
    vk.vkGetSwapchainImagesKHR(logicalDevice[], swapChain[], imageCount, C_NULL)
    resize!(swapChainImages, imageCount[])
    vk.vkGetSwapchainImagesKHR(logicalDevice[], swapChain[], imageCount, swapChainImages)
end

#################### 8.Image view ####################
function createImageViews()
    for image in swapChainImages
        components = vk.VkComponentMapping(
            vk.VK_COMPONENT_SWIZZLE_IDENTITY, #r::VkComponentSwizzle
            vk.VK_COMPONENT_SWIZZLE_IDENTITY, #g::VkComponentSwizzle
            vk.VK_COMPONENT_SWIZZLE_IDENTITY, #b::VkComponentSwizzle
            vk.VK_COMPONENT_SWIZZLE_IDENTITY #a::VkComponentSwizzle
        )
        subresourceRange = vk.VkImageSubresourceRange(
            vk.VK_IMAGE_ASPECT_COLOR_BIT, #aspectMask::VkImageAspectFlags
            0, #baseMipLevel::UInt32
            1, #levelCount::UInt32
            0, #baseArrayLayer::UInt32
            1, #layerCount::UInt32
        )
        createInfo = Ref(vk.VkImageViewCreateInfo(
            vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, #sType::VkStructureType
            C_NULL, #pNext::Ptr{Cvoid}
            0, #flags::VkImageViewCreateFlags
            image, #image::VkImage
            vk.VK_IMAGE_VIEW_TYPE_2D, #viewType::VkImageViewType
            swapChainImageFormat, #format::VkFormat
            components, #components::VkComponentMapping
            subresourceRange, #subresourceRange::VkImageSubresourceRange
        ))
        newImageView = Ref{vk.VkImageView}()
        if (vk.vkCreateImageView(logicalDevice[], createInfo, C_NULL, newImageView) != vk.VK_SUCCESS)
            println("failed to create image views!")
        end
        push!(swapChainImageViews, newImageView[])
    end
end

#################### 9.Graphic pipeline ####################
function createShaderModule(code, codeSize)
    createInfo = Ref(vk.VkShaderModuleCreateInfo(
        vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        0, #flags::VkShaderModuleCreateFlags
        codeSize, #codeSize::Csize_t
        code, #pCode::Ptr{UInt32}
    ))

    shaderModule = Ref{vk.VkShaderModule}()
    if (vk.vkCreateShaderModule(logicalDevice[], createInfo, C_NULL, shaderModule) != vk.VK_SUCCESS)
        println("failed to create shader module!")
    end
    shaderModule[]
end

function readFile(filePath)
    file = Base.read(filePath)
    size = filesize(filePath)
    file, size
end

function createGraphicsPipeline()
    vertShaderCode, vertSize = readFile("vert.spv")
    fragShaderCode, fragSize = readFile("frag.spv")

    vertShaderModule = createShaderModule(pointer(vertShaderCode), vertSize)
    fragShaderModule = createShaderModule(pointer(fragShaderCode), fragSize)

    vertShaderStageInfo = vk.VkPipelineShaderStageCreateInfo(
        vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        0, #flags::VkPipelineShaderStageCreateFlags
        vk.VK_SHADER_STAGE_VERTEX_BIT, #stage::VkShaderStageFlagBits
        vertShaderModule, #_module::VkShaderModule
        Base.unsafe_convert(Cstring, "main"), #pName::Cstring
        C_NULL #pSpecializationInfo::Ptr{VkSpecializationInfo}
    )

    fragShaderStageInfo = vk.VkPipelineShaderStageCreateInfo(
        vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        0, #flags::VkPipelineShaderStageCreateFlags
        vk.VK_SHADER_STAGE_FRAGMENT_BIT, #stage::VkShaderStageFlagBits
        fragShaderModule, #_module::VkShaderModule
        Base.unsafe_convert(Cstring, "main"), #pName::Cstring
        C_NULL #pSpecializationInfo::Ptr{VkSpecializationInfo}
    )

    shaderStages = [vertShaderStageInfo, fragShaderStageInfo]

    vertexInputInfo = Ref(vk.VkPipelineVertexInputStateCreateInfo(
        vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        0, #flags::VkPipelineVertexInputStateCreateFlags
        0, #vertexBindingDescriptionCount::UInt32
        C_NULL, #pVertexBindingDescriptions::Ptr{VkVertexInputBindingDescription}
        0, #vertexAttributeDescriptionCount::UInt32
        C_NULL, #pVertexAttributeDescriptions::Ptr{VkVertexInputAttributeDescription}
    ))

    inputAssembly = Ref(vk.VkPipelineInputAssemblyStateCreateInfo(
        vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        0, #flags::VkPipelineInputAssemblyStateCreateFlags
        vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, #topology::VkPrimitiveTopology
        vk.VK_FALSE #primitiveRestartEnable::VkBool32
    ))

    viewports = [vk.VkViewport(
        0.0, #x::Cfloat
        0.0, #y::Cfloat
        swapChainExtent.width, #width::Cfloat
        swapChainExtent.height, #height::Cfloat
        0.0, #minDepth::Cfloat
        1.0 #maxDepth::Cfloat
    )]

    scissors = [vk.VkRect2D(
        vk.VkOffset2D(0, 0), #offset::VkOffset2D
        swapChainExtent, #extent::VkExtent2D
    )]

    viewportState = Ref(vk.VkPipelineViewportStateCreateInfo(
        vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        0, #flags::VkPipelineViewportStateCreateFlags
        1, #viewportCount::UInt32
        pointer(viewports), #pViewports::Ptr{VkViewport}
        1, #scissorCount::UInt32
        pointer(scissors) #pScissors::Ptr{VkRect2D}
    ))

    rasterizer = Ref(vk.VkPipelineRasterizationStateCreateInfo(
        vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        0, #flags::VkPipelineRasterizationStateCreateFlags
        vk.VK_FALSE, #depthClampEnable::VkBool32
        vk.VK_FALSE, #rasterizerDiscardEnable::VkBool32
        vk.VK_POLYGON_MODE_FILL, #polygonMode::VkPolygonMode
        vk.VK_CULL_MODE_BACK_BIT, #cullMode::VkCullModeFlags
        vk.VK_FRONT_FACE_CLOCKWISE, #frontFace::VkFrontFace
        vk.VK_FALSE, #depthBiasEnable::VkBool32
        0.0, #depthBiasConstantFactor::Cfloat
        0.0, #depthBiasClamp::Cfloat
        0.0, #depthBiasSlopeFactor::Cfloat
        1.0 #lineWidth::Cfloat
    ))

    multisampling = Ref(vk.VkPipelineMultisampleStateCreateInfo(
        vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        0, #flags::VkPipelineMultisampleStateCreateFlags
        vk.VK_SAMPLE_COUNT_1_BIT, #rasterizationSamples::VkSampleCountFlagBits
        vk.VK_FALSE, #sampleShadingEnable::VkBool32
        1.0, #minSampleShading::Cfloat
        C_NULL,#pSampleMask::Ptr{VkSampleMask}
        vk.VK_FALSE, #alphaToCoverageEnable::VkBool32
        vk.VK_FALSE #alphaToOneEnable::VkBool32
    ))

    colorBlendAttachments = [vk.VkPipelineColorBlendAttachmentState(
        vk.VK_FALSE, #blendEnable::VkBool32
        vk.VK_BLEND_FACTOR_ONE, #srcColorBlendFactor::VkBlendFactor
        vk.VK_BLEND_FACTOR_ZERO, #dstColorBlendFactor::VkBlendFactor
        vk.VK_BLEND_OP_ADD, #colorBlendOp::VkBlendOp
        vk.VK_BLEND_FACTOR_ONE, #srcAlphaBlendFactor::VkBlendFactor
        vk.VK_BLEND_FACTOR_ZERO, #dstAlphaBlendFactor::VkBlendFactor
        vk.VK_BLEND_OP_ADD, #alphaBlendOp::VkBlendOp
        vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT #colorWriteMask::VkColorComponentFlags
    )]

    colorBlending = Ref(vk.VkPipelineColorBlendStateCreateInfo(
        vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        0, #flags::VkPipelineColorBlendStateCreateFlags
        vk.VK_FALSE, #logicOpEnable::VkBool32
        vk.VK_LOGIC_OP_COPY, #logicOp::VkLogicOp
        1, #attachmentCount::UInt32
        pointer(colorBlendAttachments), #pAttachments::Ptr{VkPipelineColorBlendAttachmentState}
        (0.0, 0.0, 0.0, 0.0), #blendConstants::NTuple{4, Cfloat}
    ))

    pipelineLayoutInfo = Ref(vk.VkPipelineLayoutCreateInfo(
        vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        0, #flags::VkPipelineLayoutCreateFlags
        0, #setLayoutCount::UInt32
        C_NULL, #pSetLayouts::Ptr{VkDescriptorSetLayout}
        0, #pushConstantRangeCount::UInt32
        C_NULL #pPushConstantRanges::Ptr{VkPushConstantRange}
    ))
    
    if (vk.vkCreatePipelineLayout(logicalDevice[], pipelineLayoutInfo, C_NULL, pipelineLayout) != vk.VK_SUCCESS)
        println("failed to create pipeline layout!")
    end

    pipelineInfo = Ref(vk.VkGraphicsPipelineCreateInfo(
        vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        0, #flags::VkPipelineCreateFlags
        2, #stageCount::UInt32
        pointer(shaderStages), #pStages::Ptr{VkPipelineShaderStageCreateInfo}
        pointer_from_objref(vertexInputInfo), #pVertexInputState::Ptr{VkPipelineVertexInputStateCreateInfo}
        pointer_from_objref(inputAssembly), #pInputAssemblyState::Ptr{VkPipelineInputAssemblyStateCreateInfo}
        C_NULL, #pTessellationState::Ptr{VkPipelineTessellationStateCreateInfo}
        pointer_from_objref(viewportState), #pViewportState::Ptr{VkPipelineViewportStateCreateInfo}
        pointer_from_objref(rasterizer), #pRasterizationState::Ptr{VkPipelineRasterizationStateCreateInfo}
        pointer_from_objref(multisampling), #pMultisampleState::Ptr{VkPipelineMultisampleStateCreateInfo}
        C_NULL, #pDepthStencilState::Ptr{VkPipelineDepthStencilStateCreateInfo}
        pointer_from_objref(colorBlending), #pColorBlendState::Ptr{VkPipelineColorBlendStateCreateInfo}
        C_NULL, #pDynamicState::Ptr{VkPipelineDynamicStateCreateInfo}
        pipelineLayout[], #layout::VkPipelineLayout
        renderPass[], #renderPass::VkRenderPass
        0, #subpass::UInt32
        vk.VK_NULL_HANDLE, #basePipelineHandle::VkPipeline
        -1 #basePipelineIndex::Int32
    ))

    if (vk.vkCreateGraphicsPipelines(logicalDevice[], C_NULL, 1, pipelineInfo, C_NULL, graphicsPipeline) != vk.VK_SUCCESS)
        println("failed to create graphics pipeline!")
    end

    vk.vkDestroyShaderModule(logicalDevice[], fragShaderModule, C_NULL)
    vk.vkDestroyShaderModule(logicalDevice[], vertShaderModule, C_NULL)
end

#################### 9.0.Render Pass ####################
function createRenderPass()
    colorAttachments = [vk.VkAttachmentDescription(
        0, #flags::VkAttachmentDescriptionFlags
        swapChainImageFormat, #format::VkFormat
        vk.VK_SAMPLE_COUNT_1_BIT, #samples::VkSampleCountFlagBits
        vk.VK_ATTACHMENT_LOAD_OP_CLEAR, #loadOp::VkAttachmentLoadOp
        vk.VK_ATTACHMENT_STORE_OP_STORE, #storeOp::VkAttachmentStoreOp
        vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE, #stencilLoadOp::VkAttachmentLoadOp
        vk.VK_ATTACHMENT_STORE_OP_DONT_CARE, #stencilStoreOp::VkAttachmentStoreOp
        vk.VK_IMAGE_LAYOUT_UNDEFINED, #initialLayout::VkImageLayout
        vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR #finalLayout::VkImageLayout
    )]

    colorAttachmentRefs = [vk.VkAttachmentReference(
        0, #attachment::UInt32
        vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL #layout::VkImageLayout
    )]


    subpasses = [vk.VkSubpassDescription(
        0, #flags::VkSubpassDescriptionFlags
        vk.VK_PIPELINE_BIND_POINT_GRAPHICS, #pipelineBindPoint::VkPipelineBindPoint
        0, #inputAttachmentCount::UInt32
        C_NULL, #pInputAttachments::Ptr{VkAttachmentReference}
        1, #colorAttachmentCount::UInt32
        pointer(colorAttachmentRefs), #pColorAttachments::Ptr{VkAttachmentReference}
        C_NULL, #pResolveAttachments::Ptr{VkAttachmentReference}
        C_NULL, #pDepthStencilAttachment::Ptr{VkAttachmentReference}
        0, #preserveAttachmentCount::UInt32
        C_NULL, #pPreserveAttachments::Ptr{UInt32}
    )]

    dependencices = [vk.VkSubpassDependency(
        vk.VK_SUBPASS_EXTERNAL, #srcSubpass::UInt32
        0, #dstSubpass::UInt32
        vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, #srcStageMask::VkPipelineStageFlags
        vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, #dstStageMask::VkPipelineStageFlags
        0, #srcAccessMask::VkAccessFlags
        vk.VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, #dstAccessMask::VkAccessFlags
        0 #dependencyFlags::VkDependencyFlags
    )]

    renderPassInfo = Ref(vk.VkRenderPassCreateInfo(
        vk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        0, #flags::VkRenderPassCreateFlags
        1, #attachmentCount::UInt32
        pointer(colorAttachments), #pAttachments::Ptr{VkAttachmentDescription}
        1, #subpassCount::UInt32
        pointer(subpasses), #pSubpasses::Ptr{VkSubpassDescription}
        1, #dependencyCount::UInt32
        pointer(dependencices) #pDependencies::Ptr{VkSubpassDependency}
    ))

    if (vk.vkCreateRenderPass(logicalDevice[], renderPassInfo, C_NULL, renderPass) != vk.VK_SUCCESS)
        println("failed to create render pass!")
    end
end

#################### 10.Create framebuffers ####################
function createFramebuffers()
    resize!(swapChainFramebuffers, length(swapChainImageViews))
    for i = 1 : length(swapChainImageViews)
        attachments = [swapChainImageViews[i]]
        framebufferInfo = Ref(vk.VkFramebufferCreateInfo(
            vk.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO, #sType::VkStructureType
            C_NULL, #pNext::Ptr{Cvoid}
            0, #flags::VkFramebufferCreateFlags
            renderPass[], #renderPass::VkRenderPass
            1, #attachmentCount::UInt32
            pointer(attachments), #pAttachments::Ptr{VkImageView}
            swapChainExtent.width, #width::UInt32
            swapChainExtent.height, #height::UInt32
            1 #layers::UInt32
        ))
        framebuffer= Ref{vk.VkFramebuffer}()
        if (vk.vkCreateFramebuffer(logicalDevice[], framebufferInfo, C_NULL, framebuffer) != vk.VK_SUCCESS)
            println("failed to create framebuffer!")
        end
        swapChainFramebuffers[i] = framebuffer[]
    end
end

#################### 11.Create command pool ####################
function createCommandPool()
    queueFamilyIndices = findQueueFamilies(physicalDevice)
    poolInfo = Ref(vk.VkCommandPoolCreateInfo(
        vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        0, #flags::VkCommandPoolCreateFlags
        queueFamilyIndices.graphicsFamily #queueFamilyIndex::UInt32
    ))

    if (vk.vkCreateCommandPool(logicalDevice[], poolInfo, C_NULL, commandPool) != vk.VK_SUCCESS)
        println("failed to create command pool!")
    end
end

function createCommandBuffers()
    resize!(commandBuffers, length(swapChainFramebuffers))

    allocInfo = Ref(vk.VkCommandBufferAllocateInfo(
        vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        commandPool[], #commandPool::VkCommandPool
        vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY, #level::VkCommandBufferLevel
        length(commandBuffers) #commandBufferCount::UInt32
    ))
    if (vk.vkAllocateCommandBuffers(logicalDevice[], allocInfo, pointer(commandBuffers)) != vk.VK_SUCCESS)
        println("failed to allocate command buffers!")
    end

    for i = 1 : length(commandBuffers)
        beginInfo = Ref(vk.VkCommandBufferBeginInfo(
            vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, #sType::VkStructureType
            C_NULL, #pNext::Ptr{Cvoid}
            vk.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT, #flags::VkCommandBufferUsageFlags
            C_NULL #pInheritanceInfo::Ptr{VkCommandBufferInheritanceInfo}
        ))
        if (vk.vkBeginCommandBuffer(commandBuffers[i], beginInfo) != vk.VK_SUCCESS)
            println("failed to begin recording command buffer!")
        end
        
        clearColors = [vk.VkClearValue(vk.VkClearColorValue((0.0, 0.0, 0.0, 1.0)))]
        renderPassInfo = Ref(vk.VkRenderPassBeginInfo(
            vk.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO, #sType::VkStructureType
            C_NULL, #pNext::Ptr{Cvoid}
            renderPass[], #renderPass::VkRenderPass
            swapChainFramebuffers[i], #framebuffer::VkFramebuffer
            vk.VkRect2D(vk.VkOffset2D(0, 0), swapChainExtent), #renderArea::VkRect2D
            1, #clearValueCount::UInt32
            pointer(clearColors) #pClearValues::Ptr{VkClearValue}
        ))

        vk.vkCmdBeginRenderPass(commandBuffers[i], renderPassInfo, vk.VK_SUBPASS_CONTENTS_INLINE)
        vk.vkCmdBindPipeline(commandBuffers[i], vk.VK_PIPELINE_BIND_POINT_GRAPHICS, graphicsPipeline[])
        vk.vkCmdDraw(commandBuffers[i], 3, 1, 0, 0)
        vk.vkCmdEndRenderPass(commandBuffers[i])
        if (vk.vkEndCommandBuffer(commandBuffers[i]) != vk.VK_SUCCESS)
            println("failed to record command buffer!")
        end
    end
end

#################### 12.Rendering ####################
function drawFrame()
    pFence = pointer_from_objref(Ref(inFlightFences[currentFrame]))
    vk.vkWaitForFences(logicalDevice[], 1, pFence, vk.VK_TRUE, typemax(UInt64))
    vk.vkResetFences(logicalDevice[], 1, pFence)

    imageIndex = Ref{UInt32}()
    vk.vkAcquireNextImageKHR(logicalDevice[], swapChain[], typemax(UInt64), imageAvailableSemaphores[currentFrame], C_NULL, imageIndex)
    waitSemaphores = [imageAvailableSemaphores[currentFrame]]
    waitDstStageMask = Ref(vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT)
    signalSemaphores = [renderFinishedSemaphores[currentFrame]]
    submitInfo = Ref(vk.VkSubmitInfo(
        vk.VK_STRUCTURE_TYPE_SUBMIT_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        1, #waitSemaphoreCount::UInt32
        pointer(waitSemaphores), #pWaitSemaphores::Ptr{VkSemaphore}
        pointer_from_objref(waitDstStageMask), #pWaitDstStageMask::Ptr{VkPipelineStageFlags}
        1, #commandBufferCount::UInt32
        pointer_from_objref(Ref(commandBuffers[imageIndex[] + 1])), #pCommandBuffers::Ptr{VkCommandBuffer}
        1, #signalSemaphoreCount::UInt32
        pointer(signalSemaphores) #pSignalSemaphores::Ptr{VkSemaphore}
    ))

    if (vk.vkQueueSubmit(graphicsQueue[], 1, submitInfo, inFlightFences[currentFrame]) != vk.VK_SUCCESS)
        println("failed to submit draw command buffer!")
    end

    presentInfo = Ref(vk.VkPresentInfoKHR(
        vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        1, #waitSemaphoreCount::UInt32
        pointer(signalSemaphores), #pWaitSemaphores::Ptr{VkSemaphore}
        1, #swapchainCount::UInt32
        pointer_from_objref(swapChain), #pSwapchains::Ptr{VkSwapchainKHR}
        pointer_from_objref(imageIndex), #pImageIndices::Ptr{UInt32}
        C_NULL #pResults::Ptr{VkResult}
    ))
    vk.vkQueuePresentKHR(presentQueue[], presentInfo)
    vk.vkDeviceWaitIdle(logicalDevice[])
    global currentFrame = currentFrame % MAX_FRAMES_IN_FLIGHT + 1
end

function createSyncObjects()
    resize!(imageAvailableSemaphores, MAX_FRAMES_IN_FLIGHT)
    resize!(renderFinishedSemaphores, MAX_FRAMES_IN_FLIGHT)
    resize!(inFlightFences, MAX_FRAMES_IN_FLIGHT)
    semaphoreInfo = Ref(vk.VkSemaphoreCreateInfo(
        vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        0 #flags::VkSemaphoreCreateFlags
    ))
    fenceInfo = Ref(vk.VkFenceCreateInfo(
        vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, #sType::VkStructureType
        C_NULL, #pNext::Ptr{Cvoid}
        vk.VK_FENCE_CREATE_SIGNALED_BIT #flags::VkFenceCreateFlags
    ))
    for i = 1 : MAX_FRAMES_IN_FLIGHT
        imageAvailableSemaphore = Ref{vk.VkSemaphore}()
        renderFinishedSemaphore = Ref{vk.VkSemaphore}()
        inFlightFence = Ref{vk.VkFence}()
        if (vk.vkCreateSemaphore(logicalDevice[], semaphoreInfo, C_NULL, imageAvailableSemaphore) != vk.VK_SUCCESS ||
            vk.vkCreateSemaphore(logicalDevice[], semaphoreInfo, C_NULL, renderFinishedSemaphore) != vk.VK_SUCCESS ||
            vk.vkCreateFence(logicalDevice[], fenceInfo, C_NULL, inFlightFence) != vk.VK_SUCCESS)
            println("failed to create synchronization objects for a frame!")
        end
        imageAvailableSemaphores[i] = imageAvailableSemaphore[]
        renderFinishedSemaphores[i] = renderFinishedSemaphore[]
        inFlightFences[i] = inFlightFence[]
    end
end

function vkDestoryInstanceCallback()
    println("callback")
end



#################### 0.Setup ####################
function initVulkan()
    if (createInstance() != vk.VK_SUCCESS)
        println("failed to create instance!")
        exit(-1)
    end

    createSurface()
    pickPhysicalDevice()
    createLogicalDevice()
    createSwapChain()
    createImageViews()
    createRenderPass()
    createGraphicsPipeline()
    createFramebuffers()
    createCommandPool()
    createCommandBuffers()
    createSyncObjects()
end

function initWindow()
    GLFW.Init()
    GLFW.WindowHint(GLFW.CLIENT_API, GLFW.NO_API)
    GLFW.WindowHint(GLFW.RESIZABLE, false)
    # Create a window and its OpenGL context
    global window = GLFW.CreateWindow(WIDTH, HEIGHT, "Vulkan")
end

function mainLoop()
    # Loop until the user closes the window
    while !GLFW.WindowShouldClose(window)
        # Poll for and process events
        GLFW.PollEvents()
        # Render here
        drawFrame()
    end
    vk.vkDeviceWaitIdle(logicalDevice[])
end

function cleanup()
    for i = 1 : MAX_FRAMES_IN_FLIGHT
        vk.vkDestroySemaphore(logicalDevice[], renderFinishedSemaphores[i], C_NULL)
        vk.vkDestroySemaphore(logicalDevice[], imageAvailableSemaphores[i], C_NULL)
        vk.vkDestroyFence(logicalDevice[], inFlightFences[i], C_NULL)
    end
    vk.vkDestroyCommandPool(logicalDevice[], commandPool[], C_NULL)
    for framebuffer in swapChainFramebuffers
        vk.vkDestroyFramebuffer(logicalDevice[], framebuffer, C_NULL)
    end
    vk.vkDestroyPipeline(logicalDevice[], graphicsPipeline[], C_NULL)
    vk.vkDestroyPipelineLayout(logicalDevice[], pipelineLayout[], C_NULL)
    vk.vkDestroyRenderPass(logicalDevice[], renderPass[], C_NULL)
    for imageView in swapChainImageViews
        vk.vkDestroyImageView(logicalDevice[], imageView, C_NULL)
    end
    vk.vkDestroySwapchainKHR(logicalDevice[], swapChain[], C_NULL)
    vk.vkDestroyDevice(logicalDevice[], C_NULL)
    vk.vkDestroySurfaceKHR(instance[], surface, C_NULL)
    vk.vkDestroyInstance(instance[], C_NULL)
    GLFW.DestroyWindow(window)
    GLFW.Terminate()
end

initWindow()
initVulkan()
mainLoop()
cleanup()